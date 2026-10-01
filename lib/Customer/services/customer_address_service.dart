import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAddressService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<String?> _getCustomerId() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('customer_profiles')
        .select('customer_id')
        .eq('user_id', uid)
        .maybeSingle();
    return row?['customer_id'] as String?;
  }

  /// Get all saved addresses for current customer
  Future<List<Map<String, dynamic>>> getSavedAddresses() async {
    final cid = await _getCustomerId();
    if (cid == null) return [];

    try {
      final res = await _client
          .from('saved_addresses')
          .select()
          .eq('customer_id', cid)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
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
    final cid = await _getCustomerId();
    if (cid == null) return null;

    final coords = '$latitude,$longitude';

    if (isDefault) {
      await _client
          .from('saved_addresses')
          .update({'is_default': false})
          .eq('customer_id', cid);
    }

    final res = await _client
        .from('saved_addresses')
        .insert({
      'customer_id': cid,
      'label': label,
      'address_line': addressLine,
      'city': city,
      'state': state,
      'postcode': postcode,
      'coordinates': coords,
      'is_default': isDefault,
    })
        .select()
        .single();

    if (isDefault) {
      await setDefaultAddress(res['address_id'], '$addressLine, $city');
    }

    return res;
  }

  /// Set selected address as active default
  Future<void> setDefaultAddress(String addressId, String fullAddress) async {
    final cid = await _getCustomerId();
    if (cid == null) return;

    // Reset other defaults
    await _client
        .from('saved_addresses')
        .update({'is_default': false})
        .eq('customer_id', cid);

    // Set selected to default
    await _client
        .from('saved_addresses')
        .update({'is_default': true})
        .eq('address_id', addressId);

    // Update customer profile header address
    await _client
        .from('customer_profiles')
        .update({'default_address': fullAddress})
        .eq('customer_id', cid);
  }

  /// Reverse geocode coordinates using OpenStreetMap Nominatim
  Future<Map<String, String>> reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final res = await http.get(url, headers: {'User-Agent': 'LocalLifeApp/1.0'});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        final road = addr['road'] ?? addr['suburb'] ?? '';
        final building = addr['building'] ?? addr['house_number'] ?? '';
        final addressLine = building.isNotEmpty ? '$building, $road' : (road.isNotEmpty ? road : (data['display_name'] ?? ''));
        final city = addr['city'] ?? addr['town'] ?? addr['municipality'] ?? 'Kuala Lumpur';
        final state = addr['state'] ?? 'Wilayah Persekutuan Kuala Lumpur';
        final postcode = addr['postcode'] ?? '50450';

        return {
          'addressLine': addressLine.toString().trim(),
          'city': city.toString().trim(),
          'state': state.toString().trim(),
          'postcode': postcode.toString().trim(),
        };
      }
    } catch (_) {}

    return {
      'addressLine': 'Jalan Ampang',
      'city': 'Kuala Lumpur',
      'state': 'Selangor',
      'postcode': '50450',
    };
  }

  /// Forward geocode query to Lat/Lng
  Future<Map<String, dynamic>?> searchLocation(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&countrycodes=my&limit=1',
      );
      final res = await http.get(url, headers: {'User-Agent': 'LocalLifeApp/1.0'});

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