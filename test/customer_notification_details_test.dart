import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/models/customer_notification_content.dart';
import 'package:fyp2/Customer/services/customer_notification_service.dart';
import 'package:fyp2/Customer/screens/notifications/customer_notification_screen.dart';
import 'package:fyp2/Customer/screens/browsing/customer_provider_detail_screen.dart';
import 'package:fyp2/shared/chat/chat_inbox_screen.dart';
import 'package:fyp2/shared/chat/chat_service.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'customer_accounts_chat_test.dart' as capture;

class ActivityNotices extends CustomerNotificationService {
  ActivityNotices(SupabaseClient client) : super(client: client);
  @override
  Future<List<Map<String, dynamic>>> getNotifications() async => [
    {
      'notification_id': 'suspended',
      'created_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
      'event_key': 'account.suspended',
      'title': 'Account suspended',
      'message': 'Please contact support about your account.',
      'notification_type': 'System',
      'is_read': true,
    },
    {
      'notification_id': 'profile',
      'created_at': DateTime.now().toIso8601String(),
      'event_key': 'customer.activity',
      'title': 'Profile preferences updated',
      'message':
          'Your bio was updated.\nYour preferred service order was updated.',
      'notification_type': 'System',
      'is_read': false,
    },
  ];
}

void main() {
  late SupabaseClient client;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
    for (final entry in {
      'Roboto': 'assets/fonts/roboto-regular.ttf',
      'HomeServeCJK': 'assets/fonts/noto-sans-sc-regular.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    client = SupabaseClient(
      'https://fixture.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());
  tearDown(() => AppLanguage.instance.select('en'));

  test('suspension is determined by event, not arbitrary message text', () {
    expect(
      CustomerNotificationContent.isSuspension({
        'event_key': 'account.suspended',
      }),
      true,
    );
    expect(
      CustomerNotificationContent.isSuspension({
        'event_key': 'account.reactivated',
        'message': 'Previously suspended',
      }),
      false,
    );
    expect(
      CustomerNotificationContent.isSuspension({
        'title': 'Account status updated',
        'message': 'suspended',
      }),
      false,
    );
  });
  for (final locale in ['en', 'zh', 'ms']) {
    test(
      'all changed fields translate in $locale while admin reasons remain verbatim',
      () async {
        await AppLanguage.instance.select(locale);
        final text = CustomerNotificationContent.message({
          'event_key': 'customer.activity',
          'message':
              'Your bio was updated.\nYour preferred service order was updated.',
        });
        expect(
          text,
          '${tr('Your bio was updated.')}\n${tr('Your preferred service order was updated.')}',
        );
        if (locale != 'en') expect(text, isNot(contains('Your bio')));
        expect(
          CustomerNotificationContent.message({
            'event_key': 'account.suspended',
            'message': 'Keep this administrator reason unchanged.',
          }),
          endsWith('Keep this administrator reason unchanged.'),
        );
      },
    );
    testWidgets(
      'read suspension remains red and activity details fit in $locale',
      (t) async {
        capture.pixel(t);
        await AppLanguage.instance.select(locale);
        await t.pumpWidget(
          capture.app(
            CustomerNotificationScreen(service: ActivityNotices(client)),
          ),
        );
        await t.pumpAndSettle();
        final icon = t.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
        expect(icon.color, CustomerTheme.danger);
        final warning = t.widget<Text>(find.text(tr('Account suspended')));
        expect(warning.style?.color, CustomerTheme.danger);
        expect(
          find.textContaining(tr('Your bio was updated.')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await capture.proof(t, 'notification-details-$locale');
      },
    );
  }
  testWidgets('customer inbox and provider search use actual profile photo URL', (
    t,
  ) async {
    capture.pixel(t);
    const photo = 'https://fixture.invalid/provider.jpg';
    final service = ChatService(
      rpc: (name, params) async => name == 'chat_provider_search'
          ? [
              {
                'provider_id': 'provider',
                'business_name': 'Provider',
                'profile_photo_url': photo,
              },
            ]
          : [
              {
                'conversation_id': 'chat',
                'peer_name': 'Provider',
                'profile_photo_url': photo,
                'preview': 'Hello',
              },
            ],
    );
    await t.pumpWidget(capture.app(ChatInboxScreen(service: service)));
    await t.pumpAndSettle();
    expect(
      t.widget<ProviderAvatar>(find.byType(ProviderAvatar)).photoUrl,
      photo,
    );
    await t.enterText(find.byType(TextField), 'Provider');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(find.byType(ProviderAvatar), findsNWidgets(2));
    expect(
      t
          .widgetList<ProviderAvatar>(find.byType(ProviderAvatar))
          .every((w) => w.photoUrl == photo),
      true,
    );
    // Flutter's test HTTP client returns 400: verify graceful image-error fallback.
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
