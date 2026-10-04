import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/services/customer_address_service.dart';

void main() {
  test('address RPC responses', () async {
    final c = SupabaseClient(
      'https://fixture.invalid',
      'test',
      httpClient: MockClient(
        (r) async => r.url.path.endsWith('customer_delete_address')
            ? http.Response('', 204, request: r)
            : http.Response(
                '{"address_id":"x"}',
                200,
                request: r,
                headers: {'content-type': 'application/json'},
              ),
      ),
    );
    final s = CustomerAddressService(client: c);
    await s.setDefaultAddress('x', 'test');
    await s.deleteAddress('x');
    await c.dispose();
  });
}
