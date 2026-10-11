import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/Customer/screens/payment/customer_checkout_screen.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_workflow_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      for (final entry in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            File(
              '$root/${entry.value}',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await loader.load();
      }
    }
  });
  testWidgets(
    'setup failure is inline, retained on refresh and recovers after setup',
    (t) async {
      capture.pixel(t);
      var configured = false;
      final service = CustomerTransactionService(
        rpc: (_, p) async => fixtures.booking(status: 'Confirmed'),
        invoke: (_, p) async {
          if (!configured)
            throw const FunctionException(
              status: 503,
              details: {
                'code': 'checkout_setup_required',
                'error': 'Bank checkout is temporarily unavailable.',
              },
            );
          return {
            'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_fixture',
            'test_mode': true,
          };
        },
      );
      await t.pumpWidget(
        capture.app(
          CustomerCheckoutScreen(
            bookingId: 'booking',
            transactions: service,
            launchCheckout: (_) async => true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Provider acceptance'), findsOneWidget);
      expect(find.text('Bank payment'), findsOneWidget);
      expect(find.text('Payment confirmation'), findsOneWidget);
      await t.tap(find.text('Open secure payment'));
      await t.pumpAndSettle();
      expect(find.text('Payment unavailable'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('View receipt'), findsNothing);
      await capture.proof(t, 'payment-setup-needed');
      configured = true;
      await t.tap(find.text('Open secure payment'));
      await t.pumpAndSettle();
      expect(find.text('Payment unavailable'), findsNothing);
      expect(find.text('Reopen bank payment'), findsOneWidget);
      expect(find.text('View receipt'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('bank browser launch failure never advances to opened state', (
    t,
  ) async {
    capture.pixel(t);
    final service = CustomerTransactionService(
      rpc: (_, p) async => fixtures.booking(status: 'Confirmed'),
      invoke: (_, p) async => {
        'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_fixture',
        'test_mode': true,
      },
    );
    await t.pumpWidget(
      capture.app(
        CustomerCheckoutScreen(
          bookingId: 'booking',
          transactions: service,
          launchCheckout: (_) async => false,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Open secure payment'));
    await t.pumpAndSettle();
    expect(
      find.text('The bank page could not open. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Reopen bank payment'), findsNothing);
    expect(find.text('View receipt'), findsNothing);
  });
  testWidgets('automatic checks stop after server verified payment', (t) async {
    capture.pixel(t);
    bool paid = false;
    int reads = 0;
    final service = CustomerTransactionService(
      rpc: (_, p) async {
        reads++;
        return fixtures.booking(status: 'Confirmed', paid: paid);
      },
      invoke: (_, p) async => {
        'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_fixture',
        'test_mode': true,
      },
    );
    await t.pumpWidget(
      capture.app(
        CustomerCheckoutScreen(
          bookingId: 'booking',
          transactions: service,
          launchCheckout: (_) async => true,
        ),
      ),
    );
    await t.pumpAndSettle();
    await capture.proof(t, 'payment-ready');
    await t.tap(find.text('Open secure payment'));
    await t.pumpAndSettle();
    expect(find.text('View receipt'), findsNothing);
    paid = true;
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.text('View receipt'), findsOneWidget);
    await capture.proof(t, 'payment-confirmed');
    final count = reads;
    await t.pump(const Duration(seconds: 65));
    expect(reads, count);
    expect(t.takeException(), isNull);
  });
  testWidgets('status polling is bounded and cancelled on page exit', (
    t,
  ) async {
    int reads = 0;
    final service = CustomerTransactionService(
      rpc: (_, p) async {
        reads++;
        return fixtures.booking(status: 'Confirmed');
      },
      invoke: (_, p) async => {
        'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_fixture',
        'test_mode': true,
      },
    );
    await t.pumpWidget(
      capture.app(
        CustomerCheckoutScreen(
          bookingId: 'booking',
          transactions: service,
          launchCheckout: (_) async => true,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Open secure payment'));
    await t.pumpAndSettle();
    for (var i = 0; i < 13; i++) {
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
    }
    expect(reads, 14); // initial read + post-launch read + 12 bounded checks
    await t.pump(const Duration(minutes: 2));
    expect(reads, 14);
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
}
