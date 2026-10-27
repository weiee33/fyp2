import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/services/customer_access.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:fyp2/shared/mobile_auth_service.dart';
import 'package:fyp2/shared/mobile_session_gate.dart';
import 'package:fyp2/shared/portal_entry_screen.dart';

Map<String, dynamic> storedSession({bool expired = false}) {
  final expiry =
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + (expired ? -120 : 3600);
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'HS256'})}.${encode({'sub': 'customer-id', 'exp': expiry})}.fixture',
    'refresh_token': 'fixture-refresh',
    'expires_in': 3600,
    'expires_at': expiry,
    'token_type': 'bearer',
    'user': {
      'id': 'customer-id',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'fixture@example.invalid',
      'created_at': '2026-10-01T00:00:00Z',
      // Restoration must ignore this deliberately wrong editable role.
      'user_metadata': {'role': 'admin'},
      'app_metadata': {},
    },
  };
}

class RestoreFixture {
  final requests = <http.Request>[];
  String role = 'customer';
  bool active = true, offline = false, revoked = false;
  int identityStatus = 200;
  Completer<void>? identityWait;
  MockClient transport() => MockClient((request) async {
    requests.add(request);
    Object response;
    var status = 200;
    switch (request.url.path) {
      case '/auth/v1/token':
        if (revoked) {
          status = 400;
          response = {
            'code': 'refresh_token_not_found',
            'msg': 'Refresh token is invalid',
          };
        } else {
          response = storedSession();
        }
      case '/auth/v1/logout':
        response = {};
      case '/rest/v1/rpc/account_identity':
        await identityWait?.future;
        if (offline) throw http.ClientException('Fixture is offline');
        status = identityStatus;
        response = status == 200
            ? {'role': role, 'is_active': active, 'user_id': 'customer-id'}
            : {
                'code': status == 403 ? '42501' : 'XX000',
                'message': 'Identity unavailable',
              };
      default:
        throw StateError('Unexpected endpoint ${request.url.path}');
    }
    return http.Response(
      jsonEncode(response),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  });

  late final client = SupabaseClient(
    'https://fixture.invalid',
    'fixture-key',
    httpClient: transport(),
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
  );
  MobileAuthService get service => MobileAuthService(client: client);
  Future<void> seed({bool expired = false}) => client.auth.setInitialSession(
    jsonEncode(storedSession(expired: expired)),
  );
}

class ControlledRestore extends MobileAuthService {
  int attempts = 0;
  final results = <Completer<MobileAccountRole?>>[];
  @override
  Future<MobileAccountRole?> restoreSession() {
    attempts++;
    final result = Completer<MobileAccountRole?>();
    results.add(result);
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RestoreFixture fixture;
  setUp(() async {
    fixture = RestoreFixture();
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
  });
  tearDown(() async {
    await fixture.client.dispose();
    CustomerAccess.instance.accept(const {});
  });

  test('no saved session shows login without requesting identity', () async {
    expect(await fixture.service.restoreSession(), isNull);
    expect(fixture.requests, isEmpty);
  });
  for (final role in MobileAccountRole.values) {
    test('saved ${role.name} uses canonical identity, not metadata', () async {
      fixture.role = role.name;
      await fixture.seed();
      expect(await fixture.service.restoreSession(), role);
      expect(fixture.client.auth.currentSession, isNotNull);
      expect(fixture.requests.single.url.path, '/rest/v1/rpc/account_identity');
    });
  }
  test(
    'saved suspended customer remains signed in with restricted access',
    () async {
      fixture.active = false;
      await fixture.seed();
      expect(
        await fixture.service.restoreSession(),
        MobileAccountRole.customer,
      );
      expect(CustomerAccess.instance.restricted, isTrue);
      expect(fixture.client.auth.currentSession, isNotNull);
    },
  );
  test('expired access token refreshes before canonical lookup', () async {
    await fixture.seed(expired: true);
    expect(await fixture.service.restoreSession(), MobileAccountRole.customer);
    expect(fixture.requests.map((r) => r.url.path), [
      '/auth/v1/token',
      '/rest/v1/rpc/account_identity',
    ]);
    final refresh = fixture.requests.first;
    expect(refresh.url.queryParameters['grant_type'], 'refresh_token');
    expect(jsonDecode(refresh.body)['refresh_token'], 'fixture-refresh');
    expect(fixture.client.auth.currentSession!.isExpired, isFalse);
  });
  test(
    'revoked refresh token returns login without opening customer home',
    () async {
      fixture.revoked = true;
      await fixture.seed(expired: true);
      expect(await fixture.service.restoreSession(), isNull);
      expect(fixture.client.auth.currentSession, isNull);
      expect(
        fixture.requests.any((r) => r.url.path.contains('account_identity')),
        isFalse,
      );
    },
  );
  test(
    'offline identity check retains session and succeeds on retry',
    () async {
      await fixture.seed();
      fixture.offline = true;
      await expectLater(
        fixture.service.restoreSession(),
        throwsA(isA<http.ClientException>()),
      );
      expect(fixture.client.auth.currentSession, isNotNull);
      expect(
        fixture.requests.any((r) => r.url.path.endsWith('logout')),
        isFalse,
      );
      fixture.offline = false;
      expect(
        await fixture.service.restoreSession(),
        MobileAccountRole.customer,
      );
    },
  );
  test('identity server error does not sign out the saved account', () async {
    await fixture.seed();
    fixture.identityStatus = 503;
    await expectLater(
      fixture.service.restoreSession(),
      throwsA(isA<PostgrestException>()),
    );
    expect(fixture.client.auth.currentSession, isNotNull);
  });
  test('definitive access denial clears the restored session', () async {
    await fixture.seed();
    fixture.identityStatus = 403;
    expect(await fixture.service.restoreSession(), isNull);
    expect(fixture.client.auth.currentSession, isNull);
  });
  test(
    'canonical administrator cannot restore into mobile customer home',
    () async {
      await fixture.seed();
      fixture.role = 'admin';
      expect(await fixture.service.restoreSession(), isNull);
      expect(fixture.client.auth.currentSession, isNull);
    },
  );
  test(
    'late identity response cannot reopen an explicitly logged-out account',
    () async {
      await fixture.seed();
      fixture.identityWait = Completer<void>();
      final restoring = fixture.service.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await fixture.client.auth.signOut(scope: SignOutScope.local);
      fixture.identityWait!.complete();
      expect(await restoring, isNull);
      expect(CustomerAccess.instance.customer, isFalse);
    },
  );

  test(
    'Flutter persisted session survives client restart until explicit logout',
    () async {
      const key = 'sb-fixture-auth-token';
      Future<void> boot() async {
        await Supabase.initialize(
          url: 'https://fixture.invalid',
          anonKey: 'fixture-key',
          httpClient: fixture.transport(),
          debug: false,
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            authFlowType: AuthFlowType.implicit,
          ),
        );
      }

      await boot();
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'fixture@example.invalid',
          password: 'fixture-password',
        );
        final prefs = await SharedPreferences.getInstance();
        // SDK persistence is asynchronous on the auth event stream.
        for (var i = 0; i < 30 && prefs.getString(key) == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(prefs.getString(key), isNotNull);
        await Supabase.instance.dispose();
        await boot();
        expect(
          await MobileAuthService().restoreSession(),
          MobileAccountRole.customer,
        );
        expect(
          fixture.requests.where(
            (r) => r.url.queryParameters['grant_type'] == 'password',
          ),
          hasLength(1),
        );
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
        for (var i = 0; i < 30 && prefs.getString(key) != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(prefs.getString(key), isNull);
        await Supabase.instance.dispose();
        await boot();
        expect(await MobileAuthService().restoreSession(), isNull);
      } finally {
        await Supabase.instance.dispose();
      }
    },
  );

  Widget app(ControlledRestore auth) => MaterialApp(
    theme: CustomerTheme.lightTheme,
    home: MobileSessionGate(
      service: auth,
      homeBuilder: (role) => Scaffold(body: Text('home:${role.name}')),
    ),
  );
  testWidgets('startup waits for identity without flashing login', (t) async {
    final auth = ControlledRestore();
    await t.pumpWidget(app(auth));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(PortalEntryScreen), findsNothing);
    auth.results.single.complete(MobileAccountRole.customer);
    await t.pumpAndSettle();
    expect(find.text('home:customer'), findsOneWidget);
    expect(find.byType(PortalEntryScreen), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(find.text('home:customer'), findsOneWidget);
    expect(auth.attempts, 1);
  });
  testWidgets('offline startup offers retry without showing login or home', (
    t,
  ) async {
    final auth = ControlledRestore();
    await t.pumpWidget(app(auth));
    auth.results.single.completeError(http.ClientException('Offline'));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(PortalEntryScreen), findsNothing);
    expect(find.text('home:customer'), findsNothing);
    await t.tap(find.text('Retry'));
    await t.pump();
    auth.results.last.complete(MobileAccountRole.customer);
    await t.pumpAndSettle();
    expect(find.text('home:customer'), findsOneWidget);
  });
  testWidgets('no session opens shared login', (t) async {
    final auth = ControlledRestore();
    await t.pumpWidget(app(auth));
    auth.results.single.complete(null);
    await t.pumpAndSettle();
    expect(find.byType(PortalEntryScreen), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
  });
}
