import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/models/booking_model.dart';
import 'package:fyp2/Customer/services/customer_image_service.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_detail_screen.dart';
import 'package:fyp2/Customer/screens/payment/customer_checkout_screen.dart';
import 'package:fyp2/Customer/screens/payment/customer_receipt_screen.dart';

Map<String, dynamic> booking({String status = 'Pending', bool paid = false}) => {
  'booking_id': '11111111-1111-4111-8111-111111111111',
  'provider_id': '22222222-2222-4222-8222-222222222222',
  'service_name': 'House cleaning', 'business_name': 'Local Cleaners',
  'booking_date': '2026-10-05', 'scheduled_time': '09:00:00',
  'customer_address': '123 Service Street, Kuala Lumpur', 'total_amount': 180,
  'booking_status': status, 'can_pay': status == 'Confirmed' && !paid,
  'can_cancel': status == 'Pending' || status == 'Confirmed',
  'can_review': status == 'Completed' && paid,
  'payment': paid ? {'payment_status': 'Success', 'payment_amount': 180, 'payment_method': 'FPX', 'fpx_transaction_ref': 'pi_verified'} : null,
  'disputes': <dynamic>[],
};
void pixel3a(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 808);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
void main() {
  test('booking sends saved address and idempotency token, never customer identity or price', () async {
    late Map<String, dynamic> payload;
    final service = CustomerTransactionService(rpc: (name, params) async {
      expect(name, 'customer_create_booking'); payload = params; return booking();
    });
    final token = CustomerTransactionService.newRequestId();
    await service.createPendingBooking(serviceId: 'service', addressId: 'address', date: DateTime(2026, 10, 5), scheduledTime: '09:00', requestId: token);
    expect(payload['p_request_id'], token);
    expect(payload['p_address_id'], 'address');
    expect(payload.keys.any((key) => key.contains('amount') || key.contains('customer') || key.contains('provider')), false);
  });
  test('slot conflict is propagated without inventing a booking', () async {
    final service = CustomerTransactionService(rpc: (_, params) async => throw const PostgrestException(message: 'Slot was reserved', code: '23P01'));
    await expectLater(service.createPendingBooking(serviceId: 's', addressId: 'a', date: DateTime(2026, 10, 5), scheduledTime: '09:00', requestId: 'id'), throwsA(isA<PostgrestException>()));
  });
  test('gateway request supplies booking only', () async {
    final service = CustomerTransactionService(invoke: (name, params) async {
      expect(name, 'customer-checkout'); expect(params, {'booking_id': 'booking'});
      return {'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_fixture', 'test_mode': true};
    });
    expect((await service.startCheckout('booking')).testMode, true);
  });
  test('malicious gateway URLs are rejected', () {
    for (final url in ['http://checkout.stripe.com/', 'https://checkout.stripe.com.evil.invalid/', 'https://user@checkout.stripe.com/', 'https://checkout.stripe.com:8443/']) {
      expect(() => CheckoutSession.fromJson({'checkout_url': url}), throwsFormatException);
    }
  });
  test('image upload rejects oversized files and disguised nonimages', () {
    expect(() => CustomerImageService.validate(Uint8List.fromList('not an image'.codeUnits), 'jpg'), throwsFormatException);
    expect(() => CustomerImageService.validate(Uint8List(CustomerImageService.maxBytes + 1), 'png'), throwsFormatException);
    expect(CustomerImageService.validate(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]), '.PNG'), 'image/png');
  });
  for (final state in ['Pending', 'Confirmed', 'Completed']) {
    testWidgets('$state booking exposes only permitted next steps on Pixel 3a', (tester) async {
      pixel3a(tester);
      final data = booking(status: state, paid: state == 'Completed');
      final service = CustomerTransactionService(rpc: (_, params) async => data);
      await tester.pumpWidget(MaterialApp(home: CustomerBookingDetailScreen(bookingId: data['booking_id'], transactions: service)));
      await tester.pumpAndSettle();
      expect(find.text('Continue to payment'), state == 'Confirmed' ? findsOneWidget : findsNothing);
      expect(find.text('Write a review'), state == 'Completed' ? findsOneWidget : findsNothing);
      expect(find.text('View receipt'), state == 'Completed' ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('opening the FPX browser never creates a receipt; only verified refresh does', (tester) async {
    pixel3a(tester); bool paid = false; int opened = 0;
    final service = CustomerTransactionService(rpc: (_, params) async => booking(status: 'Confirmed', paid: paid),
      invoke: (_, params) async => {'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_fixture', 'test_mode': true});
    await tester.pumpWidget(MaterialApp(home: CustomerCheckoutScreen(bookingId: 'booking', transactions: service, launchCheckout: (_) async { opened++; return true; })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open secure payment')); await tester.pumpAndSettle();
    expect(opened, 1); expect(find.text('View receipt'), findsNothing);
    paid = true;
    await tester.scrollUntilVisible(find.text('Check payment status'), 250);
    await tester.tap(find.text('Check payment status')); await tester.pumpAndSettle();
    expect(find.text('View receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('gateway configuration errors stay visible and cannot report success', (tester) async {
    final service = CustomerTransactionService(rpc: (_, params) async => booking(status: 'Confirmed'),
      invoke: (_, params) async => throw const FunctionException(status: 503, details: {'error': 'FPX test checkout is not configured yet.'}));
    await tester.pumpWidget(MaterialApp(home: CustomerCheckoutScreen(bookingId: 'booking', transactions: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open secure payment')); await tester.pumpAndSettle();
    expect(find.text('FPX test checkout is not configured yet.'), findsOneWidget);
    expect(find.text('View receipt'), findsNothing);
  });
  testWidgets('receipt displays verified payment amount even if booking display differs', (tester) async {
    final data = booking(status: 'Confirmed', paid: true)..['total_amount'] = 999;
    final service = CustomerTransactionService(rpc: (_, params) async => {'booking': data, 'payment': data['payment']});
    await tester.pumpWidget(MaterialApp(home: CustomerReceiptScreen(bookingId: 'booking', transactions: service)));
    await tester.pumpAndSettle();
    expect(find.text('RM 180.00'), findsOneWidget); expect(find.text('RM 999.00'), findsNothing);
  });
}
