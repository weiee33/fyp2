import 'package:fyp2/Customer/screens/home/customer_root_nav_screen.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/widgets/malaysia_phone_field.dart';
import 'package:fyp2/Customer/widgets/customer_dialogs.dart';
import 'package:fyp2/Customer/services/customer_recovery_service.dart';
import 'package:fyp2/Customer/services/customer_profile_service.dart';
import 'package:fyp2/Customer/screens/profile/customer_profile_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_edit_profile_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_settings_screen.dart';
import 'package:fyp2/Customer/screens/auth/customer_forgot_password_screen.dart';
import 'package:fyp2/shared/chat/chat_service.dart';
import 'package:fyp2/shared/chat/chat_screen.dart';
import 'package:fyp2/shared/chat/chat_inbox_screen.dart';

Map<String, dynamic> session() {
  String encode(Object p) =>
      base64Url.encode(utf8.encode(jsonEncode(p))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'HS256'})}.${encode({'sub': '00000000-0000-4000-8000-000000000001', 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
    'refresh_token': 'fixture',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': '00000000-0000-4000-8000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'fixture@example.invalid',
      'created_at': '2026-10-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  };
}

class FixtureProfile extends CustomerProfileService {
  Map<String, dynamic> data = {
    'full_name': 'Wei Ee',
    'email': 'fixture@example.invalid',
    'phone': '+60102049818',
    'bio': 'Looking after my home',
    'gender': 'Prefer not to say',
    'birthday': '2004-03-03',
    'service_preferences': ['Cleaning'],
  };
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>> getProfileData() async => data;
  @override
  Future<List<String>> getPreferenceOptions() async => [
    'Cleaning',
    'Plumbing',
    'Electrical',
  ];
  @override
  Future<void> updateProfile({
    required String fullName,
    required String phone,
    String? photoUrl,
    required List<String> preferences,
    String? bio,
    String? gender,
    String? birthday,
  }) async {
    saved = {
      'full_name': fullName,
      'phone': phone,
      'bio': bio,
      'gender': gender,
      'birthday': birthday,
    };
  }
}

class FixtureRecovery extends CustomerRecoveryService {
  int requested = 0, attempted = 0;
  @override
  Future<void> requestCode(String email) async {
    requested++;
  }

  @override
  Future<void> changePassword({
    required String email,
    required String code,
    required String password,
  }) async {
    attempted++;
    throw const AuthException('The code is invalid. Request a new code.');
  }
}

void pixel(WidgetTester t) {
  t.view.physicalSize = const Size(393, 808);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> proof(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('proof')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.tools/customer-ui/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget app(Widget home) => RepaintBoundary(
  key: const ValueKey('proof'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: CustomerTheme.lightTheme,
    home: home,
  ),
);

void main() {
  setUpAll(() async {
    const fontRoot = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (fontRoot.isNotEmpty) {
      for (final entry in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            File(
              '$fontRoot/${entry.value}',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await loader.load();
      }
    }
  });
  test(
    'Malaysian numbers are canonical and national input rejects country/trunk prefixes',
    () {
      expect(MalaysiaPhone.international('102049818'), '+60102049818');
      expect(MalaysiaPhone.national('+60 10-204 9818'), '102049818');
      expect(MalaysiaPhone.national('0102049818'), '102049818');
      expect(MalaysiaPhone.validate('0102049818'), isNotNull);
      expect(MalaysiaPhone.validate('60102049818'), isNotNull);
      expect(() => MalaysiaPhone.international('123'), throwsFormatException);
    },
  );
  for (final scenario in ['success', 'bad_code', 'provider', 'update_retry']) {
    test(
      'password recovery $scenario enforces OTP then customer identity then update',
      () async {
        final calls = <String>[];
        var verifyCalls = 0, updates = 0;
        final client = SupabaseClient(
          'https://fixture.invalid',
          'fixture-key',
          authOptions: const AuthClientOptions(
            autoRefreshToken: false,
            authFlowType: AuthFlowType.implicit,
          ),
          httpClient: MockClient((request) async {
            calls.add(request.url.path);
            http.Response response(Object value, [int status = 200]) =>
                http.Response(
                  jsonEncode(value),
                  status,
                  headers: {'content-type': 'application/json'},
                  request: request,
                );
            if (request.url.path.endsWith('/recover')) {
              expect(
                jsonDecode(request.body)['email'],
                'fixture@example.invalid',
              );
              expect(request.body.contains('password'), false);
              return response({});
            }
            if (request.url.path.endsWith('/verify')) {
              verifyCalls++;
              expect(jsonDecode(request.body)['type'], 'recovery');
              return scenario == 'bad_code'
                  ? response({
                      'msg': 'Token has expired or is invalid',
                      'code': 'otp_expired',
                    }, 403)
                  : response(session());
            }
            if (request.url.path.endsWith('/account_identity'))
              return response({
                'role': scenario == 'provider' ? 'provider' : 'customer',
                'user_id': 'different-app-id',
              });
            if (request.url.path.endsWith('/user')) {
              updates++;
              expect(
                jsonDecode(request.body)['password'],
                'fixture-new-password',
              );
              if (scenario == 'update_retry' && updates == 1)
                return response({'msg': 'Temporary failure'}, 500);
              return response(session()['user']);
            }
            if (request.url.path.endsWith('/logout')) return response({});
            throw StateError('Unexpected endpoint');
          }),
        );
        final service = CustomerRecoveryService(client: client);
        await service.requestCode('fixture@example.invalid');
        Future<void> change() => service.changePassword(
          email: 'fixture@example.invalid',
          code: '123456',
          password: 'fixture-new-password',
        );
        if (scenario == 'bad_code' || scenario == 'provider') {
          await expectLater(change(), throwsA(isA<AuthException>()));
          expect(updates, 0);
        } else if (scenario == 'update_retry') {
          await expectLater(change(), throwsA(isA<AuthException>()));
          await change();
          expect(verifyCalls, 1);
          expect(updates, 2);
        } else {
          await change();
          expect(
            calls.indexOf('/auth/v1/verify'),
            lessThan(calls.indexOf('/rest/v1/rpc/account_identity')),
          );
          expect(
            calls.indexOf('/rest/v1/rpc/account_identity'),
            lessThan(calls.indexOf('/auth/v1/user')),
          );
        }
        await service.dispose();
      },
    );
  }
  testWidgets('phone prefix remains visible and error dialog requires OK', (
    t,
  ) async {
    pixel(t);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                MalaysiaPhoneField(controller: controller),
                TextButton(
                  onPressed: () => CustomerDialogs.show(
                    context,
                    message: 'Please check your number.',
                  ),
                  child: const Text('Validate'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('+60'), findsOneWidget);
    await t.enterText(find.byType(TextFormField), '102049818');
    expect(controller.text, '102049818');
    await t.tap(find.text('Validate'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tapAt(const Offset(2, 2));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
    'forgot password requests code before attempting password change',
    (t) async {
      pixel(t);
      final service = FixtureRecovery();
      await t.pumpWidget(app(CustomerForgotPasswordScreen(service: service)));
      await t.pumpAndSettle();
      await proof(t, 'password-reset');
      await t.enterText(
        find.byType(TextFormField).at(0),
        'fixture@example.invalid',
      );
      await t.enterText(
        find.byType(TextFormField).at(1),
        'fixture-new-password',
      );
      await t.enterText(
        find.byType(TextFormField).at(2),
        'fixture-new-password',
      );
      await t.ensureVisible(find.text('Confirm change password'));
      await t.tap(find.text('Confirm change password'));
      await t.pumpAndSettle();
      expect(service.requested, 1);
      expect(service.attempted, 0);
      expect(find.text('Check your email'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await proof(t, 'password-code');
      await t.enterText(find.byType(TextField), '123456');
      await t.tap(find.text('Verify & change password'));
      await t.pumpAndSettle();
      expect(service.attempted, 1);
      expect(
        find.text('The code is invalid. Request a new code.'),
        findsOneWidget,
      );
      expect(find.text('Password changed'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'profile dashboard fits Pixel 3a and has meaningful account shortcuts',
    (t) async {
      pixel(t);
      await t.pumpWidget(
        app(
          CustomerRootNavScreen(
            initialTab: 3,
            pages: [
              const Text('Explore tab'),
              const Text('Bookings tab'),
              const Text('Notifications tab'),
              CustomerProfileScreen(service: FixtureProfile()),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Wei Ee'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.byTooltip('Account settings'), findsNothing);
      expect(find.text('Edit your profile  ›'), findsNothing);
      expect(find.text('Account & Security'), findsNothing);
      expect(find.text('My Addresses'), findsOneWidget);
      expect(t.takeException(), isNull);
      await proof(t, 'profile');
    },
  );
  testWidgets('edit profile saves canonical phone and new private details', (
    t,
  ) async {
    pixel(t);
    final service = FixtureProfile();
    await t.pumpWidget(
      app(
        CustomerEditProfileScreen(profileData: service.data, service: service),
      ),
    );
    await t.pumpAndSettle();
    await proof(t, 'edit-profile');
    await t.tap(find.text('Phone'));
    await t.pumpAndSettle();
    expect(find.text('+60'), findsOneWidget);
    expect(
      t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '102049818',
    );
    await t.enterText(find.byType(TextFormField), '1123456789');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(service.saved?['phone'], '+601123456789');
    expect(service.saved?['bio'], 'Looking after my home');
    expect(find.text('Profile updated successfully'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('settings and account security fit Pixel 3a', (t) async {
    pixel(t);
    await t.pumpWidget(app(const CustomerSettingsScreen()));
    await t.pumpAndSettle();
    await proof(t, 'settings');
    expect(t.takeException(), isNull);
    await t.pumpWidget(
      app(CustomerAccountSecurityScreen(service: FixtureProfile())),
    );
    await t.pumpAndSettle();
    await proof(t, 'account-security');
    expect(find.text('Change Password'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'chat send retries reuse id and keep text until server confirms',
    (t) async {
      pixel(t);
      final attempts = <Map<String, dynamic>>[];
      final service = ChatService(
        rpc: (name, p) async {
          if (name == 'chat_history')
            return {
              'peer_name': 'Local Cleaners',
              'can_send': true,
              'blocked': false,
              'cleared_through': 0,
              'messages': <dynamic>[],
            };
          if (name == 'chat_manage') return null;
          if (name == 'chat_send') {
            attempts.add({...p});
            if (attempts.length == 1)
              throw const PostgrestException(message: 'Please retry');
            return {
              'message_id': 1,
              'body': p['p_body'],
              'is_mine': true,
              'created_at': '2026-10-03T10:00:00Z',
            };
          }
          throw StateError(name);
        },
      );
      await t.pumpWidget(
        app(ConversationScreen(conversationId: 'chat', service: service)),
      );
      await t.pumpAndSettle();
      await proof(t, 'chat');
      await t.enterText(find.byType(TextField), 'Is 10 am available?');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(find.text('Please retry'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Is 10 am available?',
      );
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(attempts.length, 2);
      expect(attempts[0]['p_request_id'], attempts[1]['p_request_id']);
      expect(
        attempts[0].keys,
        unorderedEquals(['p_conversation_id', 'p_body', 'p_request_id']),
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('inbox search and pin/delete actions reach guarded RPCs', (
    t,
  ) async {
    pixel(t);
    final actions = <String>[];
    var pinned = false;
    final service = ChatService(
      rpc: (name, p) async {
        if (name == 'chat_inbox')
          return [
            {
              'conversation_id': 'chat',
              'peer_name': 'Local Cleaners',
              'preview': 'Hello',
              'pinned': pinned,
              'unread_count': 2,
            },
          ];
        if (name == 'chat_provider_search')
          return [
            {
              'provider_id': 'provider',
              'business_name': 'Local Cleaners',
              'city': 'Kuala Lumpur',
            },
          ];
        if (name == 'chat_manage') {
          actions.add(p['p_action']);
          pinned = p['p_action'] == 'pin';
          return null;
        }
        throw StateError(name);
      },
    );
    await t.pumpWidget(app(ChatInboxScreen(service: service)));
    await t.pumpAndSettle();
    await proof(t, 'chats');
    await t.drag(find.text('Local Cleaners'), const Offset(-200, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Pin'));
    await t.pumpAndSettle();
    expect(actions, ['pin']);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Chat actions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last);
    await t.pumpAndSettle();
    expect(find.text('Delete this chat?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(actions, ['pin']);
    await t.enterText(find.byType(TextField), 'Local');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text('Kuala Lumpur'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('chat refresh removes history cleared on another device', (
    t,
  ) async {
    pixel(t);
    var cleared = 0;
    final service = ChatService(
      rpc: (name, p) async {
        if (name == 'chat_manage') return null;
        if (name == 'chat_history')
          return {
            'peer_name': 'Provider',
            'can_send': true,
            'blocked': false,
            'cleared_through': cleared,
            'messages': [
              {
                'message_id': 2,
                'body': 'New reply',
                'is_mine': false,
                'created_at': '2026-10-03T10:01:00Z',
              },
              if (cleared == 0)
                {
                  'message_id': 1,
                  'body': 'Cleared old message',
                  'is_mine': true,
                  'created_at': '2026-10-03T10:00:00Z',
                },
            ],
          };
        throw StateError(name);
      },
    );
    await t.pumpWidget(
      app(ConversationScreen(conversationId: 'chat', service: service)),
    );
    await t.pumpAndSettle();
    expect(find.text('Cleared old message'), findsOneWidget);
    cleared = 1;
    await t.drag(find.byType(ListView).first, const Offset(0, -350));
    await t.pumpAndSettle();
    expect(find.text('Cleared old message'), findsNothing);
    expect(find.text('New reply'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'blocked chats remain reachable after deleting from normal inbox',
    (t) async {
      pixel(t);
      var called = false;
      final service = ChatService(
        rpc: (name, p) async {
          if (name == 'chat_inbox') return [];
          if (name == 'chat_blocked') {
            called = true;
            return [
              {
                'conversation_id': 'hidden-chat',
                'peer_name': 'Blocked Provider',
                'blocked': true,
                'pinned': false,
                'unread_count': 0,
              },
            ];
          }
          throw StateError(name);
        },
      );
      await t.pumpWidget(app(ChatInboxScreen(service: service)));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Blocked chats'));
      await t.pumpAndSettle();
      expect(called, true);
      expect(find.text('Blocked Provider'), findsOneWidget);
      expect(find.text('Blocked chats'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
