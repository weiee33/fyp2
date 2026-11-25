import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
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

  static const _unavailable =
      'Address lookup is unavailable. Enter the address manually.';

  Future<dynamic> _lookup(
    Map<String, dynamic> body, {
    Future<Map<String, String>?> Function()? deviceFallback,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return (await _client.functions.invoke(
          'customer-geocode',
          body: body,
        )).data;
      } on FunctionException catch (e) {
        final details = e.details;
        final code = details is Map ? details['code'] : null;
        // Older deployments identified a Photon rejection only by its message.
        final legacyRejection =
            details is Map &&
            details['error'] ==
                'Address lookup is unavailable. You can enter the address manually.';
        final providerUnavailable =
            (e.status == 502 &&
                (code == 'provider_unavailable' || legacyRejection)) ||
            (e.status == 503 &&
                const {
                  'provider_unavailable',
                  'provider',
                  'decode',
                }.contains(code));
        if (deviceFallback != null &&
            (providerUnavailable ||
                code == 'provider_busy' && e.status == 429)) {
          final fields = await deviceFallback();
          if (fields != null) return fields;
        }
        if (e.status == 429 && code != 'provider_busy' && attempt < 2) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        if (e.status == 429) {
          throw const FormatException('Address lookup is busy. Please retry.');
        }
        if (e.status >= 500) throw const FormatException(_unavailable);
        throw FormatException(
          details is Map
              ? details['error']?.toString() ?? _unavailable
              : _unavailable,
        );
      }
    }
    throw const FormatException('Address lookup is busy. Please retry.');
  }

  Future<Map<String, String>> reverseGeocode(double lat, double lng) async {
    final data = await _lookup({
      'kind': 'reverse',
      'lat': lat,
      'lng': lng,
    }, deviceFallback: () => _deviceAddress(lat, lng));
    return Map<String, String>.from(data as Map);
  }

  Future<Map<String, String>?> _deviceAddress(double lat, double lng) async {
    final geocoder = GeocodingPlatform.instance;
    if (geocoder == null) return null;
    try {
      final places = await geocoder
          .placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 6));
      for (final place in places) {
        if (place.isoCountryCode?.trim().toUpperCase() != 'MY') continue;
        final road = [place.subThoroughfare, place.thoroughfare]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' ');
        final line = _first([
          if ((place.thoroughfare ?? '').trim().isNotEmpty) road,
          place.street,
          place.name,
        ]);
        final city = _first([place.locality, place.subAdministrativeArea]);
        final territory = const {
          'kuala lumpur',
          'putrajaya',
          'labuan',
        }.contains(city.toLowerCase());
        if (line.isEmpty && city.isEmpty) continue;
        return {
          'addressLine': line,
          'city': city,
          'state': _first([place.administrativeArea, if (territory) city]),
          'postcode': place.postalCode?.trim() ?? '',
        };
      }
      return null;
    } on NoResultFoundException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static String _first(List<String?> parts) => parts
      .whereType<String>()
      .map((s) => s.trim())
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');

  Future<Map<String, dynamic>?> searchLocation(String query) async {
    final data = await _lookup({'kind': 'search', 'query': query});
    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }
}
