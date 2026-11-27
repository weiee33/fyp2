import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/screens/ai/customer_ai_screen.dart';
import 'package:fyp2/Customer/screens/payment/customer_receipt_screen.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/shared/chat/chat_screen.dart';
import 'customer_accounts_chat_test.dart' as fixture;
import 'customer_ai_test.dart' as ai;
import 'customer_receipt_photo_test.dart' as receipt;

// Start on the painted text itself, where an inner text scrollable used to
// intercept the drag. Check movement of the enclosing screen's list.
Future<void> dragText(WidgetTester t, Finder text, Offset drag) async {
  final list = find.ancestor(of: text, matching: find.byType(ListView)).first;
  final position = t
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      )
      .position;
  final before = position.pixels;
  await t.drag(text, drag);
  await t.pumpAndSettle();
  expect((position.pixels - before).abs(), greaterThan(20));
}

void main() {
  testWidgets('dragging a chat message scrolls the conversation', (t) async {
    fixture.pixel(t);
    final service = receipt.PhotoChat();
    for (int id = 30; id > 0; id--) {
      service.messages.add({
        'message_id': id,
        'body': 'Message $id',
        'is_mine': id.isEven,
        'created_at': '2026-10-03T10:01:00Z',
      });
    }
    await t.pumpWidget(
      fixture.app(ConversationScreen(conversationId: 'chat', service: service)),
    );
    await t.pumpAndSettle();
    await dragText(
      t,
      find.text('Message 28').hitTestable(),
      const Offset(0, 100),
    );
    final message = find.text('Message 25').hitTestable();
    await t.longPress(message);
    await t.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets(
    'dragging formatted replies and user prompts scrolls AI history',
    (t) async {
      fixture.pixel(t);
      final service = ai.FakeAi();
      for (var id = 1; id <= 30; id++) {
        service.messages.add({
          'id': id,
          'role': id.isEven ? 'assistant' : 'user',
          'content': id.isEven ? '**Reply** $id' : 'Question $id',
        });
      }
      await t.pumpWidget(
        fixture.app(
          CustomerAiScreen(service: service, speech: ai.FakeSpeech()),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Chat history'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cleaning help'));
      await t.pumpAndSettle();
      for (final prefix in ['Reply ', 'Question ']) {
        final text = find
            .byWidgetPredicate(
              (w) =>
                  w is Text &&
                  (w.textSpan?.toPlainText().startsWith(prefix) ?? false),
            )
            .hitTestable()
            .last;
        await dragText(t, text, const Offset(0, 100));
      }
    },
  );

  testWidgets('dragging a receipt number scrolls the receipt', (t) async {
    fixture.pixel(t);
    await t.pumpWidget(
      fixture.app(
        CustomerReceiptScreen(
          bookingId: 'booking',
          transactions: CustomerTransactionService(
            rpc: (_, _) async => receipt.receiptData(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await dragText(
      t,
      find.text('receipt-123').hitTestable(),
      const Offset(0, -100),
    );
  });
}
