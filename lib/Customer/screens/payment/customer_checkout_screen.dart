import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_transaction_service.dart';
import 'customer_receipt_screen.dart';

class CustomerCheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final Map<String, dynamic> providerData;
  final Map<String, dynamic> serviceData;

  const CustomerCheckoutScreen({
    super.key,
    required this.bookingData,
    required this.providerData,
    required this.serviceData,
  });

  @override
  State<CustomerCheckoutScreen> createState() => _CustomerCheckoutScreenState();
}

class _CustomerCheckoutScreenState extends State<CustomerCheckoutScreen> {
  final CustomerTransactionService _txService = CustomerTransactionService();

  String _selectedPaymentMethod = 'Online Banking (FPX)';
  String _selectedBank = 'Maybank2U';
  bool _isProcessing = false;

  void _showBankSelector() {
    final banks = ['Maybank2U', 'CIMB Clicks', 'Public Bank', 'RHB Now', 'Hong Leong Connect'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select FPX Bank', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...banks.map((bank) => ListTile(
                title: Text(bank, style: const TextStyle(fontWeight: FontWeight.w500)),
                trailing: _selectedBank == bank ? const Icon(Icons.check_circle, color: CustomerTheme.primary) : null,
                onTap: () {
                  setState(() {
                    _selectedPaymentMethod = 'Online Banking (FPX)';
                    _selectedBank = bank;
                  });
                  Navigator.pop(ctx);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _processPayment() async {
    setState(() => _isProcessing = true);
    HapticFeedback.heavyImpact();

    try {
      // 1. Simulate Gateway Redirect Delay[cite: 449]
      await Future.delayed(const Duration(seconds: 2));

      // 2. Execute Backend Payment & Escrow logic[cite: 449, 450]
      final payment = await _txService.processFpxPayment(
        bookingId: widget.bookingData['booking_id'],
        amount: (widget.bookingData['total_amount'] as num).toDouble(),
        bankName: _selectedBank,
      );

      if (!mounted) return;

      // 3. Route to Receipt[cite: 450]
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: CustomerReceiptScreen(
              paymentData: payment,
              bookingData: widget.bookingData,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Failed: $e'), backgroundColor: CustomerTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = (widget.bookingData['total_amount'] as num).toDouble();

    return Scaffold(
      backgroundColor: CustomerTheme.background,
      appBar: AppBar(title: const Text('Secure Checkout'), elevation: 0),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            children: [
              const Text('ORDER SUMMARY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.providerData['business_name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Today, ${widget.bookingData['scheduled_time'].toString().substring(0, 5)}', style: const TextStyle(color: CustomerTheme.textSecondary)),
                    ],
                  ),
                  Text('RM ${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Locked Price', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text('RM ${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: CustomerTheme.primaryDark)),
                ],
              ),
              const SizedBox(height: 40),

              const Text('Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // FPX Selection[cite: 449]
              InkWell(
                onTap: _showBankSelector,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _selectedPaymentMethod.contains('FPX') ? CustomerTheme.primary : CustomerTheme.borderColor, width: 2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: CustomerTheme.primarySurface, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.account_balance, color: CustomerTheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Online Banking (FPX)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(_selectedBank, style: const TextStyle(color: CustomerTheme.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Escrow Protection Badge[cite: 517]
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_rounded, color: CustomerTheme.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(color: CustomerTheme.textPrimary, fontSize: 13, height: 1.4),
                          children: [
                            TextSpan(text: 'Escrow Protection: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: 'Your payment is held securely and only released to the provider when you confirm the job is complete.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Process Indicator Overlay
          if (_isProcessing)
            Container(
              color: Colors.white.withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: CustomerTheme.primary),
                    const SizedBox(height: 24),
                    const Text('Authenticating FPX Gateway...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Redirecting to $_selectedBank', style: const TextStyle(color: CustomerTheme.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _isProcessing ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton.icon(
            onPressed: _processPayment,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.lock, size: 18),
            label: Text('Pay RM ${price.toStringAsFixed(2)} Securely', style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}