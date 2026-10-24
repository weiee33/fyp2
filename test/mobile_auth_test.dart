import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/shared/mobile_auth_service.dart';
import 'package:fyp2/Customer/services/customer_access.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:fyp2/Customer/screens/auth/customer_login_screen.dart';
import 'package:fyp2/Customer/screens/auth/customer_register_screen.dart';
import 'package:fyp2/Customer/screens/auth/customer_otp_screen.dart';
import 'app_language_test.dart' show Host;
import 'customer_accounts_chat_test.dart' show proof;

class AuthFixture {
  String role = 'customer';
  bool identityDenied = false, confirmed = true, active = true;
  final requests = <http.Request>[];
  late final client = SupabaseClient(
    'https://fixture.invalid',
    'fixture-key',
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
    httpClient: MockClient((r) async {
      requests.add(r);
      Object value;
      var status = 200;
      final user = {
        'id': '00000000-0000-4000-8000-000000000001',
        'aud': 'authenticated', 'role': 'authenticated',
        'email': 'test@example.invalid', 'created_at': '2026-10-01T00:00:00Z',
        // Deliberately differs from the database role.
        'user_metadata': {'role': role == 'customer' ? 'provider' : 'customer'},
        'app_metadata': {},
      };
      switch (r.url.path) {
        case '/auth/v1/token':
        case '/auth/v1/verify':
        case '/auth/v1/signup':
          String encode(Object v) =>
              base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
          value = !confirmed && r.url.path.endsWith('/signup')
              ? user
              : {
                  'access_token':
                      '${encode({'alg': 'HS256'})}.${encode({'sub': user['id'], 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
                  'refresh_token': 'fixture-refresh',
                  'expires_in': 3600,
                  'token_type': 'bearer',
                  'user': user,
                };
        case '/rest/v1/rpc/account_identity':
          status = identityDenied ? 403 : 200;
          value = identityDenied
              ? {'code': '42501', 'message': 'Inactive account'}
              : {
                  'role': role,
                  'user_id': 'canonical-user',
                  'is_active': active,
                };
        case '/auth/v1/logout':
        case '/auth/v1/resend':
          value = {};
        default:
          throw StateError('Unexpected endpoint ${r.url}');
      }
      return http.Response(
        jsonEncode(value),
        status,
        request: r,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  MobileAuthService get service => MobileAuthService(client: client);
}

class ScreenAuth extends MobileAuthService {
  final MobileAccountRole role;
  ScreenAuth(this.role);
  @override
  Future<MobileAccountRole> login({
    required String email,
    required String password,
  }) async => role;
  @override
  Future<MobileAccountRole> verifyOtp({
    required String email,
    required String token,
  }) async => role;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'Roboto': 'assets/fonts/roboto-regular.ttf',
      'HomeServeCJK': 'assets/fonts/noto-sans-sc-regular.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    const fontRoot = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (fontRoot.isNotEmpty) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$fontRoot/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  late AuthFixture fixture;
  WidgetTester? widgetTester;
  setUp(() async {
    widgetTester = null;
    fixture = AuthFixture();
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
  });
  tearDown(() async {
    CustomerAccess.instance.accept(const {});
    if (widgetTester == null) {
      await fixture.client.dispose();
    }
    await AppLanguage.instance.select('en');
  });
  test('suspended customer can authenticate into restricted account', () async {
    fixture.active = false;
    expect(
      await fixture.service.login(
        email: 'test@example.invalid',
        password: 'secret',
      ),
      MobileAccountRole.customer,
    );
    expect(fixture.client.auth.currentSession, isNotNull);
    expect(CustomerAccess.instance.restricted, isTrue);
    fixture.active = true;
    await fixture.service.resolveRole();
    expect(CustomerAccess.instance.restricted, isFalse);
  });
  for (final role in MobileAccountRole.values) {
    test(
      '${role.name} password and OTP use canonical role, not metadata',
      () async {
        fixture.role = role.name;
        expect(
          await fixture.service.login(
            email: ' test@example.invalid ',
            password: 'secret',
          ),
          role,
        );
        expect(
          jsonDecode(fixture.requests.first.body)['email'],
          'test@example.invalid',
        );
        expect(
          await fixture.service.verifyOtp(
            email: 'test@example.invalid',
            token: '123456',
          ),
          role,
        );
        expect(fixture.client.auth.currentSession, isNotNull);
      },
    );
    test(
      '${role.name} registration records intent and normalized contact data',
      () async {
        fixture.role = role.name;
        fixture.confirmed = false;
        final registration = await fixture.service.register(
          email: ' test@example.invalid ',
          password: 'secret',
          fullName: ' Test User ',
          phone: '102049818',
          accountRole: role,
        );
        expect(registration.role, isNull);
        expect(registration.response.session, isNull);
        final body = jsonDecode(fixture.requests.single.body);
        expect(body['data'], {
          'full_name': 'Test User',
          'phone': '+60102049818',
          'role': role.name,
        });
        expect(
          fixture.requests.any((r) => r.url.path.endsWith('account_identity')),
          isFalse,
        );
      },
    );
    testWidgets('${role.name} shared login opens the matching account', (
      t,
    ) async {
      widgetTester = t;
      fixture.role = role.name;
      await t.pumpWidget(
        LanguageScope(
          child: Host(
            CustomerLoginScreen(
              service: ScreenAuth(role),
              homeBuilder: (resolved) =>
                  Scaffold(body: Text('home:${resolved.name}')),
            ),
          ),
        ),
      );
      await t.enterText(
        find.byType(TextFormField).at(0),
        'test@example.invalid',
      );
      await t.enterText(find.byType(TextFormField).at(1), 'secret');
      await t.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await t.pumpAndSettle();
      expect(find.text('home:${role.name}'), findsOneWidget);
      expect(find.byType(CustomerLoginScreen), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('${role.name} verification opens canonical account', (t) async {
      widgetTester = t;
      fixture.role = role.name;
      await t.pumpWidget(
        LanguageScope(
          child: Host(
            CustomerOtpScreen(
              email: 'test@example.invalid',
              service: ScreenAuth(role),
              homeBuilder: (resolved) =>
                  Scaffold(body: Text('home:${resolved.name}')),
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextField).first, '123456');
      await t.tap(find.widgetWithText(ElevatedButton, 'Verify & Proceed'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('home:${role.name}'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  for (final failure in ['admin', 'unknown', 'inactive']) {
    test('$failure identity clears authenticated session', () async {
      fixture.role = failure;
      fixture.identityDenied = failure == 'inactive';
      await expectLater(
        fixture.service.login(
          email: 'test@example.invalid',
          password: 'secret',
        ),
        throwsA(
          failure == 'inactive'
              ? isA<PostgrestException>()
              : isA<AuthException>(),
        ),
      );
      expect(fixture.client.auth.currentSession, isNull);
      expect(fixture.requests.last.url.path, '/auth/v1/logout');
    });
  }
  test(
    'confirmed signup still routes using database role rather than choice',
    () async {
      fixture.role = 'provider';
      final result = await fixture.service.register(
        email: 'test@example.invalid',
        password: 'secret',
        fullName: 'Test',
        phone: '102049818',
        accountRole: MobileAccountRole.customer,
      );
      expect(result.role, MobileAccountRole.provider);
    },
  );
  for (final language in ['en', 'zh', 'ms']) {
    testWidgets(
      '$language shared login and registration fit narrow enlarged text',
      (t) async {
        widgetTester = t;
        t.view.physicalSize = const Size(320, 780);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await AppLanguage.instance.select(language);
        for (final page in [
          CustomerLoginScreen(service: ScreenAuth(MobileAccountRole.customer)),
          CustomerRegisterScreen(
            service: ScreenAuth(MobileAccountRole.customer),
          ),
        ]) {
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('proof'),
              child: LanguageScope(
                child: Host(
                  MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(1.3),
                    ),
                    child: page,
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          if (page is CustomerRegisterScreen) {
            expect(find.text(tr('Account type')), findsOneWidget);
            await t.tap(find.byKey(const ValueKey('register-provider')));
            await t.pumpAndSettle();
            expect(
              t
                  .widget<Semantics>(
                    find
                        .ancestor(
                          of: find.byKey(const ValueKey('register-provider')),
                          matching: find.byType(Semantics),
                        )
                        .first,
                  )
                  .properties
                  .selected,
              isTrue,
            );
            expect(
              find.text(tr('Offer services and manage your jobs.')),
              findsOneWidget,
            );
          } else {
            expect(find.text(tr('Login')), findsNWidgets(2));
            expect(find.text('Consumer Portal'), findsNothing);
          }
          expect(t.takeException(), isNull);
          await proof(
            t,
            'shared-auth-$language-${page is CustomerRegisterScreen ? 'register' : 'login'}',
          );
        }
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
