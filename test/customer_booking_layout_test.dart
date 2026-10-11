import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:fyp2/Customer/services/customer_address_service.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_form_screen.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_detail_screen.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_workflow_test.dart' as fixtures;

class Addresses extends CustomerAddressService {
  Addresses()
    : super(
        client: SupabaseClient(
          'https://fixture.invalid',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  Future<List<Map<String, dynamic>>> getSavedAddresses() async => [
    {
      'address_id': 'address',
      'label': 'Home',
      'address_line': 'Jalan Bestari 23',
      'city': 'Jenjarom',
    },
  ];
}

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
  for (final width in [360.0, 393.0]) {
    testWidgets(
      'booking form remains usable at $width with keyboard and no slots',
      (t) async {
        capture.pixel(t);
        t.view.physicalSize = Size(width, 808);
        final transactions = CustomerTransactionService(
          rpc: (_, params) async => <dynamic>[],
        );
        await t.pumpWidget(
          capture.app(
            CustomerBookingFormScreen(
              serviceData: {
                'service_id': 'service',
                'service_name': 'Fix Leaking Faucet',
                'base_price': 50,
              },
              providerData: {'business_name': 'Local Plumbing'},
              addresses: Addresses(),
              transactions: transactions,
            ),
          ),
        );
        await t.pumpAndSettle();
        await capture.proof(t, 'booking-form-$width');
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Create booking'),
              )
              .onPressed,
          isNull,
        );
        await t.scrollUntilVisible(
          find.text('Choose another date'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Choose another date'));
        await t.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byType(TextField),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byType(TextField),
          'Please call when you arrive.',
        );
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        t.view.resetViewInsets();
      },
    );
  }
  for (final expired in [false, true]) {
    testWidgets('booking detail visual state expired=$expired', (t) async {
      capture.pixel(t);
      final data = fixtures.booking(status: 'Confirmed')
        ..['booking_date'] = '2026-10-20'
        ..['scheduled_datetime'] = '2026-10-20T01:00:00Z'
        ..['reservation_expires_at'] = DateTime.now()
            .add(Duration(minutes: expired ? -1 : 30))
            .toUtc()
            .toIso8601String();
      await t.pumpWidget(
        capture.app(
          CustomerBookingDetailScreen(
            bookingId: data['booking_id'],
            transactions: CustomerTransactionService(rpc: (_, p) async => data),
          ),
        ),
      );
      await t.pumpAndSettle();
      await capture.proof(t, expired ? 'booking-expired' : 'booking-pay');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
