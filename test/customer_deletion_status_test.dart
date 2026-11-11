import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/models/booking_model.dart';
import 'package:fyp2/Customer/widgets/booking_status.dart';

void main() {
  final cases = <(String, String?, String)>[
    ('Cancelled', null, 'Not paid'),
    ('Cancelled', 'Success', 'Paid'),
    ('Cancelled', 'Refunded', 'Refunded'),
    ('Cancelled', 'Failed', 'Payment failed'),
    ('Confirmed', null, 'Expired · Not paid'),
    ('Confirmed', 'Success', 'Paid'),
  ];
  for (final (status, payment, label) in cases) {
    testWidgets('$status / $payment shows $label', (tester) async {
      final booking = CustomerBooking.fromJson({
        'booking_id': 'booking',
        'provider_id': 'provider',
        'booking_status': status,
        'reservation_expires_at': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'payment': payment == null ? null : {'payment_status': payment},
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BookingPaymentStatus(booking: booking)),
        ),
      );
      expect(find.text(label), findsOneWidget);
      expect(find.text('Awaiting payment'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
