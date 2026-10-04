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

  Future<dynamic> _lookup(Map<String, dynamic> body) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return (await _client.functions.invoke(
          'customer-geocode',
          body: body,
        )).data;
      } on FunctionException catch (e) {
        if (e.status == 429 && attempt < 2) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        throw FormatException(
          e.details is Map
              ? e.details['error']?.toString() ??
                    'Address lookup is unavailable.'
              : 'Address lookup is unavailable. Enter the address manually.',
        );
      }
    }
    throw const FormatException('Address lookup is busy. Please retry.');
  }

  Future<Map<String, String>> reverseGeocode(double lat, double lng) async {
    final data = await _lookup({'kind': 'reverse', 'lat': lat, 'lng': lng});
    return Map<String, String>.from(data as Map);
  }

  Future<Map<String, dynamic>?> searchLocation(String query) async {
    final data = await _lookup({'kind': 'search', 'query': query});
    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }
}
