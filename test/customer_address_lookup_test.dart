import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/services/customer_address_service.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceGeocoder extends GeocodingPlatform {
  List<Placemark> places = [];
  final pins = <List<double>>[];

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double lat,
    double lng,
  ) async {
    pins.add([lat, lng]);
    return places;
  }
}

void main() {
  late DeviceGeocoder device;
  setUp(() {
    device = DeviceGeocoder();
    GeocodingPlatform.instance = device;
  });

  CustomerAddressService service(int status, Map<String, dynamic> body) {
    final client = SupabaseClient(
      'https://fixture.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/functions/v1/customer-geocode');
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    return CustomerAddressService(client: client);
  }

  test(
    'reported 502 recovers the same pin using a Malaysian device address',
    () async {
      device.places = [
        const Placemark(
          isoCountryCode: 'MY',
          thoroughfare: 'Lorong Kuda',
          locality: 'Kuala Lumpur',
          postalCode: '50088',
        ),
      ];
      final fields = await service(502, {
        'error':
            'Address lookup is unavailable. You can enter the address manually.',
      }).reverseGeocode(3.1579, 101.7116);
      expect(device.pins, [
        [3.1579, 101.7116],
      ]);
      expect(fields, {
        'addressLine': 'Lorong Kuda',
        'city': 'Kuala Lumpur',
        'state': 'Kuala Lumpur',
        'postcode': '50088',
      });
    },
  );

  test('no Malaysian result produces one manual-entry message', () async {
    device.places = [
      const Placemark(isoCountryCode: 'SG', street: 'Example Road'),
    ];
    await expectLater(
      service(503, {
        'code': 'provider_unavailable',
        'error':
            'Address lookup is unavailable. Address lookup is unavailable.',
      }).reverseGeocode(1.3, 103.8),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Address lookup is unavailable. Enter the address manually.',
        ),
      ),
    );
  });

  test(
    'access denial and internal failures do not invoke the device lookup',
    () async {
      for (final status in [401, 403, 502, 503]) {
        await expectLater(
          service(status, {
            'code': 'request',
            'error': 'Access unavailable.',
          }).reverseGeocode(3, 101),
          throwsFormatException,
        );
      }
      expect(device.pins, isEmpty);
    },
  );

  test('a successful cloud result needs no device lookup', () async {
    final fields = {
      'addressLine': 'Lorong Kuda',
      'city': 'Kuala Lumpur',
      'state': 'Kuala Lumpur',
      'postcode': '',
    };
    expect(await service(200, fields).reverseGeocode(3, 101), fields);
    expect(device.pins, isEmpty);
  });
}
