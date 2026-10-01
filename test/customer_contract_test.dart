import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/services/customer_auth_service.dart';
import 'package:fyp2/Customer/services/customer_address_service.dart';
import 'package:fyp2/Customer/services/customer_home_service.dart';
import 'package:fyp2/Provider/services/auth_service.dart';

void main() {
  const userId = '00000000-0000-4000-8000-000000000001';
  late SupabaseClient client;
  late List<http.Request> requests;
  late String databaseRole;
  late bool failIdentity;
  late bool failDirectory;
  late bool failCategories;
  late http.Request activeRequest;
  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
    request: activeRequest,
  );
  Map<String, dynamic> session() {
    String encode(Object part) =>
        base64Url.encode(utf8.encode(jsonEncode(part))).replaceAll('=', '');
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    return {
      'access_token':
          '${encode({'alg': 'HS256'})}.${encode({'sub': userId, 'exp': expiry, 'role': 'authenticated'})}.fixture',
      'refresh_token': 'fixture-refresh',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'fixture@example.invalid',
        'created_at': '2026-10-01T00:00:00Z',
        'app_metadata': {},
        'user_metadata': {'role': 'customer'},
      },
    };
  }

  setUp(() {
    requests = [];
    databaseRole = 'customer';
    failIdentity = false;
    failDirectory = false;
    failCategories = false;
    client = SupabaseClient(
      'https://fixture.example.invalid',
      'fixture-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        activeRequest = request;
        switch (request.url.path) {
          case '/auth/v1/token':
          case '/auth/v1/verify':
            return json(session());
          case '/auth/v1/logout':
            return json({});
          case '/rest/v1/rpc/account_identity':
            return failIdentity
                ? json({'code': '42501', 'message': 'Inactive account'}, 403)
                : json({
                    'user_id': 'different-application-id',
                    'role': databaseRole,
                    'customer_id': 'customer-id',
                    'full_name': 'Fixture',
                  });
          case '/rest/v1/rpc/customer_save_address':
            return json({'address_id': 'saved-id', 'is_default': true});
          case '/rest/v1/rpc/customer_set_default_address':
            return json({'address_id': 'saved-id'});
          case '/rest/v1/rpc/customer_provider_directory':
            return failDirectory
                ? json({'code': '42501', 'message': 'Denied'}, 403)
                : json([]);
          case '/rest/v1/service_categories':
            return failCategories
                ? json({'code': '42501', 'message': 'Denied'}, 403)
                : json([]);
          default:
            throw StateError('Unexpected request: ${request.url}');
        }
      }),
    );
  });
  tearDown(() async {
    await client.dispose();
  });

  test('customer password login validates the canonical identity', () async {
    await CustomerAuthService(
      client: client,
    ).login(email: 'fixture@example.invalid', password: 'fixture');
    expect(client.auth.currentSession, isNotNull);
    expect(
      requests.any((r) => r.url.path.endsWith('/account_identity')),
      isTrue,
    );
  });
  test('customer metadata cannot bypass database provider role', () async {
    databaseRole = 'provider';
    await expectLater(
      CustomerAuthService(
        client: client,
      ).login(email: 'fixture@example.invalid', password: 'fixture'),
      throwsA(isA<AuthException>()),
    );
    expect(client.auth.currentSession, isNull);
  });
  test(
    'provider login accepts database role despite conflicting metadata',
    () async {
      databaseRole = 'provider';
      await AuthService(
        client: client,
      ).login(email: 'fixture@example.invalid', password: 'fixture');
      expect(client.auth.currentSession, isNotNull);
    },
  );
  test('failed account lookup clears the newly created session', () async {
    failIdentity = true;
    await expectLater(
      CustomerAuthService(
        client: client,
      ).login(email: 'fixture@example.invalid', password: 'fixture'),
      throwsA(isA<PostgrestException>()),
    );
    expect(client.auth.currentSession, isNull);
  });
  test('customer OTP cannot enter the app with an admin role', () async {
    databaseRole = 'admin';
    await expectLater(
      CustomerAuthService(
        client: client,
      ).verifyOtp(email: 'fixture@example.invalid', token: '123456'),
      throwsA(isA<AuthException>()),
    );
    expect(client.auth.currentSession, isNull);
  });
  test('address save uses one atomic ownership-checked RPC', () async {
    final row = await CustomerAddressService(client: client).addAddress(
      label: 'Home',
      addressLine: '10 Street',
      city: 'KL',
      state: 'WP',
      postcode: '50000',
      latitude: 3.1,
      longitude: 101.6,
      isDefault: true,
    );
    expect(row!['address_id'], 'saved-id');
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/rest/v1/rpc/customer_save_address');
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['make_default'], isTrue);
    expect(body.containsKey('customer_id'), isFalse);
  });
  test('default address ignores caller-supplied header text', () async {
    await CustomerAddressService(
      client: client,
    ).setDefaultAddress('saved-id', 'Untrusted header');
    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body), {'selected_address': 'saved-id'});
  });
  test('empty directory does not fabricate providers', () async {
    expect(
      await CustomerHomeService(client: client).getRecommendedProviders(),
      isEmpty,
    );
  });
  test('directory permission failure remains an error', () async {
    failDirectory = true;
    await expectLater(
      CustomerHomeService(client: client).getRecommendedProviders(),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('empty categories do not fabricate database records', () async {
    expect(await CustomerHomeService(client: client).getCategories(), isEmpty);
  });
  test('category permission failure remains an error', () async {
    failCategories = true;
    await expectLater(
      CustomerHomeService(client: client).getCategories(),
      throwsA(isA<PostgrestException>()),
    );
  });
}
