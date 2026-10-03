import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../models/booking_model.dart';
import '../../services/customer_transaction_service.dart';

class CustomerReceiptScreen extends StatefulWidget {
  final String bookingId;
  final CustomerTransactionService? transactions;
  const CustomerReceiptScreen({
    super.key,
    required this.bookingId,
    this.transactions,
  });
  @override
  State<CustomerReceiptScreen> createState() => _CustomerReceiptScreenState();
}

class _CustomerReceiptScreenState extends State<CustomerReceiptScreen> {
  late final CustomerTransactionService _transactions =
      widget.transactions ?? CustomerTransactionService();
  Map<String, dynamic>? _receipt;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final receipt = await _transactions.getReceipt(widget.bookingId);
      if (mounted) setState(() => _receipt = receipt);
    } catch (error) {
      if (mounted) {
        setState(() => _error = bookingError(error));
        CustomerDialogs.show(
          context,
          title: 'Unable to complete',
          message: bookingError(error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    final booking = receipt == null
        ? null
        : CustomerBooking.fromJson(
            Map<String, dynamic>.from(receipt['booking'] as Map),
          );
    final payment = receipt == null
        ? null
        : Map<String, dynamic>.from(receipt['payment'] as Map);
    return Scaffold(
      appBar: AppBar(title: const Text('Payment receipt')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ] else if (booking == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            const Icon(Icons.receipt_long_outlined, size: 64),
            const SizedBox(height: 20),
            Text(
              booking.serviceName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(booking.providerName),
            const Divider(height: 32),
            _row('Booking reference', booking.shortId),
            _row(
              'Payment reference',
              payment?['fpx_transaction_ref']?.toString() ??
                  payment?['payment_id']?.toString() ??
                  '',
            ),
            _row(
              'Amount',
              'RM ${(double.tryParse(payment?['payment_amount'].toString() ?? '') ?? 0).toStringAsFixed(2)}',
            ),
            _row(
              'Payment status',
              payment?['payment_status']?.toString() ?? '',
            ),
            _row(
              'Payment method',
              payment?['payment_method']?.toString() ?? '',
            ),
            _row(
              'Appointment',
              '${booking.date} · ${booking.time} (Malaysia time)',
            ),
            _row('Booking status', booking.status),
            if (booking.status == 'Pending')
              const Text('The provider has not yet accepted this booking.'),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        SelectableText(value),
      ],
    ),
  );
}
