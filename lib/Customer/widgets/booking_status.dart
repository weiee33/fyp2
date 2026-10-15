import 'package:fyp2/shared/localization/app_language.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/booking_model.dart';

class BookingPaymentStatus extends StatelessWidget {
  final CustomerBooking booking;
  const BookingPaymentStatus({super.key, required this.booking});
  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final refunded = booking.paymentStatus == 'Refunded';
    final paid = booking.paymentStatus == 'Success';
    final expired = booking.displayStatus == 'Expired';
    final failed = booking.paymentStatus == 'Failed';
    final color = refunded
        ? const Color(0xFF516078)
        : paid
        ? const Color(0xFF157347)
        : expired || failed
        ? const Color(0xFFB42318)
        : const Color(0xFF9A5700);
    final label = refunded
        ? 'Refunded'
        : paid
        ? 'Paid'
        : expired
        ? 'Expired · Not paid'
        : failed
        ? 'Payment failed'
        : 'Awaiting payment';
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(label),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              refunded
                  ? Icons.undo_rounded
                  : paid
                  ? Icons.check_circle
                  : expired || failed
                  ? Icons.cancel
                  : Icons.schedule,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tr(label),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs only while displayed; always derives remaining time from the server deadline.
class PaymentCountdown extends StatefulWidget {
  final DateTime deadline;
  const PaymentCountdown({super.key, required this.deadline});
  @override
  State<PaymentCountdown> createState() => _PaymentCountdownState();
}

class _PaymentCountdownState extends State<PaymentCountdown> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final seconds = widget.deadline
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 86400);
    final label = seconds == 0
        ? 'Payment window ended'
        : tr("Time to pay: {0}:{1}", [
            (seconds ~/ 60).toString().padLeft(2, '0'),
            (seconds % 60).toString().padLeft(2, '0'),
          ]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: Color(0xFF9A5700), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(label),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF9A5700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BookingProgress extends StatelessWidget {
  final CustomerBooking booking;
  const BookingProgress({super.key, required this.booking});
  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final stopped =
        booking.displayStatus == 'Expired' || booking.status == 'Cancelled';
    final stage = booking.status == 'Completed'
        ? 4
        : ['In Progress', 'In-Progress'].contains(booking.status)
        ? 3
        : booking.hasReceipt
        ? 2
        : booking.status == 'Confirmed'
        ? 1
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Booking progress'),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 350),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= stage
                        ? const Color(0xFFE5F5EC)
                        : const Color(0xFFF0F1F4),
                  ),
                  child: Icon(
                    i <= stage ? Icons.check : Icons.circle_outlined,
                    size: 16,
                    color: i <= stage ? const Color(0xFF157347) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(
                      [
                        'Requested',
                        'Provider accepted',
                        'Payment received',
                        'Service in progress',
                        'Service completed',
                      ][i],
                    ),
                    style: TextStyle(
                      color: i <= stage ? Colors.black87 : Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (stopped)
          Text(
            tr("Booking {0}.", [tr(booking.displayStatus)]),
            style: const TextStyle(
              color: Color(0xFFB42318),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
