import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../home/customer_root_nav_screen.dart';

class CustomerReceiptScreen extends StatefulWidget {
  final Map<String, dynamic> paymentData;
  final Map<String, dynamic> bookingData;

  const CustomerReceiptScreen({
    super.key,
    required this.paymentData,
    required this.bookingData,
  });

  @override
  State<CustomerReceiptScreen> createState() => _CustomerReceiptScreenState();
}

class _CustomerReceiptScreenState extends State<CustomerReceiptScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingId = widget.bookingData['booking_id'].toString();
    final shortId = '#${bookingId.substring(0, 8).toUpperCase()}';
    final amount = (widget.paymentData['payment_amount'] as num).toDouble();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Animated Checkmark[cite: 518]
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: CustomerTheme.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Payment Secured',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: CustomerTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Your booking is confirmed. Funds are held securely until the job is complete.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CustomerTheme.textSecondary, fontSize: 14, height: 1.5),
              ),
            ),
            const SizedBox(height: 48),

            // Receipt Details
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: CustomerTheme.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CustomerTheme.borderColor),
              ),
              child: Column(
                children: [
                  _receiptRow('Booking ID', shortId),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  _receiptRow('Amount Held', 'RM ${amount.toStringAsFixed(2)}'),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status', style: TextStyle(color: CustomerTheme.textSecondary, fontSize: 14)),
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_rounded, size: 16, color: CustomerTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text('Paid via FPX', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                        ],
                      )
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),

            // Track Booking Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: ElevatedButton(
                onPressed: () {
                  // Route back to the root navigation shell and switch to Bookings tab (index 1)
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomerRootNavScreen(initialTab: 1)),
                        (_) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Track Booking', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: CustomerTheme.textSecondary, fontSize: 14)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: CustomerTheme.textPrimary)),
      ],
    );
  }
}