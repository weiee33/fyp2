import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAddressService {
  final SupabaseClient _client;

  CustomerAddressService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// RLS resolves the active customer through the explicit Auth identity mapping.
  Future<List<Map<String, dynamic>>> getSavedAddresses() async {
    final rows = await _client
        .from('saved_addresses')
        .select()
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Add new address and optionally set as default
  Future<Map<String, dynamic>?> addAddress({
    required String label,
    required String addressLine,
    required String city,
    required String state,
    required String postcode,
    required double latitude,
    required double longitude,
    bool isDefault = false,
  }) async {
    final result = await _client.rpc(
      'customer_save_address',
      params: {
        'address_label': label,
        'address_text': addressLine,
        'address_city': city,
        'address_state': state,
        'address_postcode': postcode,
        'latitude': latitude,
        'longitude': longitude,
        'make_default': isDefault,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// The server checks ownership and atomically updates the default and header.
  Future<void> setDefaultAddress(String addressId, String fullAddress) async {
    await _client.rpc(
      'customer_set_default_address',
      params: {'selected_address': addressId},
    );
  }

  Future<void> deleteAddress(String addressId) async {
    await _client.rpc(
      'customer_delete_address',
      params: {'p_address_id': addressId},
    );
  }

  /// Reverse geocode coordinates using OpenStreetMap Nominatim
  Future<Map<String, String>> reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'LocalLifeApp/1.0'})
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        final road = addr['road'] ?? addr['suburb'] ?? '';
        final building = addr['building'] ?? addr['house_number'] ?? '';
        final addressLine = building.isNotEmpty
            ? '$building, $road'
            : (road.isNotEmpty ? road : (data['display_name'] ?? ''));
        final city = addr['city'] ?? addr['town'] ?? addr['municipality'] ?? '';
        final state = addr['state'] ?? '';
        final postcode = addr['postcode'] ?? '';

        return {
          'addressLine': addressLine.toString().trim(),
          'city': city.toString().trim(),
          'state': state.toString().trim(),
          'postcode': postcode.toString().trim(),
        };
      }
    } catch (_) {}

    return {'addressLine': '', 'city': '', 'state': '', 'postcode': ''};
  }

  /// Forward geocode query to Lat/Lng
  Future<Map<String, dynamic>?> searchLocation(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&countrycodes=my&limit=1',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'LocalLifeApp/1.0'})
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          final first = list.first;
          return {
            'lat': double.parse(first['lat']),
            'lng': double.parse(first['lon']),
            'displayName': first['display_name'],
          };
        }
      }
    } catch (_) {}
    return null;
  }
}
