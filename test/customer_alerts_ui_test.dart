import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/screens/ai/customer_ai_screen.dart';
import 'package:fyp2/Customer/screens/notifications/customer_notification_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_settings_screen.dart';
import 'package:fyp2/Customer/widgets/customer_menu.dart';
import 'customer_ai_test.dart' as ai;
import 'customer_ux_test.dart' as ux;
import 'customer_accounts_chat_test.dart' as capture;

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'));
    await font.load();
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$root/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await icons.load();
    }
  });
  testWidgets(
    'AI menus have shared rounded surface, selected mode and working actions',
    (t) async {
      capture.pixel(t);
      await t.pumpWidget(
        capture.app(
          CustomerAiScreen(service: ai.FakeAi(), speech: ai.FakeSpeech()),
        ),
      );
      await t.tap(find.byTooltip('Assistant mode'));
      await t.pumpAndSettle();
      expect(find.byType(CustomerMenuRow), findsNWidgets(2));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(t.takeException(), isNull);
      await capture.proof(t, 'polished-ai-mode-menu');
      await t.tap(find.text('AI Agent'));
      await t.pumpAndSettle();
      expect(find.text('AI Agent'), findsOneWidget);
      await t.tap(find.byTooltip('Chat history'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Chat options'));
      await t.pumpAndSettle();
      expect(find.byType(CustomerMenuRow), findsNWidgets(2));
      await capture.proof(t, 'polished-ai-chat-menu');
      await t.tap(find.text('Rename'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );
  testWidgets(
    'All notifications distinguishes real database categories and filters consistently',
    (t) async {
      capture.pixel(t);
      final notices = ux.Notices();
      notices.rows.addAll([
        {
          'notification_id': 'three',
          'title': 'Payment verified',
          'message': 'Your receipt is available.',
          'notification_type': 'Payment',
          'is_read': true,
          'created_at': '2026-10-15T10:00:00Z',
        },
        {
          'notification_id': 'four',
          'title': 'New chat message',
          'message': 'Open your chat to read it.',
          'notification_type': 'Message',
          'is_read': true,
          'created_at': '2026-10-15T09:00:00Z',
        },
      ]);
      await t.pumpWidget(
        capture.app(CustomerNotificationScreen(service: notices)),
      );
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.event_available_rounded), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.account_balance_wallet_rounded), findsOneWidget);
      await capture.proof(t, 'polished-notification-categories');
      await t.tap(find.text('Booking'));
      await t.pumpAndSettle();
      expect(find.text('Booking accepted'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
    },
  );
  testWidgets('settings rows omit globe and logout glyphs', (t) async {
    capture.pixel(t);
    await t.pumpWidget(capture.app(const CustomerSettingsScreen()));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.language_rounded), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing);
    await capture.proof(t, 'polished-settings');
  });
}
