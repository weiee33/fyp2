import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/booking_model.dart';
import '../../services/customer_transaction_service.dart';
import 'customer_receipt_screen.dart';

class CustomerCheckoutScreen extends StatefulWidget {
  final String bookingId;
  final CustomerTransactionService? transactions;
  final Future<bool> Function(Uri)? launchCheckout;
  const CustomerCheckoutScreen({
    super.key,
    required this.bookingId,
    this.transactions,
    this.launchCheckout,
  });
  @override
  State<CustomerCheckoutScreen> createState() => _CustomerCheckoutScreenState();
}

class _CustomerCheckoutScreenState extends State<CustomerCheckoutScreen>
    with WidgetsBindingObserver {
  late final CustomerTransactionService _transactions =
      widget.transactions ?? CustomerTransactionService();
  CustomerBooking? _booking;
  String? _error;
  bool _loading = true;
  bool _processing = false;
  bool _openedGateway = false;
  bool _testMode = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _openedGateway &&
        !_processing &&
        !_loading)
      _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking = await _transactions.getBooking(widget.bookingId);
      if (mounted) setState(() => _booking = booking);
    } catch (error) {
      if (mounted) {
        setState(() => _error = bookingError(error));
        CustomerDialogs.show(
          context,
          title: 'Unable to complete',
          message: bookingError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    if (_processing || _booking?.canPay != true) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final session = await _transactions.startCheckout(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _openedGateway = true;
        _testMode = session.testMode;
      });
      final launched =
          await (widget.launchCheckout?.call(session.url) ??
              launchUrl(session.url, mode: LaunchMode.externalApplication));
      if (!launched) throw StateError('Could not open gateway');
    } catch (error) {
      if (mounted) {
        setState(() => _error = bookingError(error));
        CustomerDialogs.show(
          context,
          title: 'Unable to complete',
          message: bookingError(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        await _refreshKeepingError();
      }
    }
  }

  Future<void> _refreshKeepingError() async {
    final existing = _error;
    await _refresh();
    if (mounted && existing != null) setState(() => _error = existing);
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_loading || _processing) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              'Payment could not be completed. Please retry.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _loading || _processing ? null : _refresh,
              child: const Text('Refresh status'),
            ),
          ],
          if (booking != null) ...[
            const SizedBox(height: 24),
            Text(
              booking.serviceName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(booking.providerName),
            const SizedBox(height: 16),
            Text('${booking.date} · ${booking.time} (Malaysia time)'),
            Text(booking.address),
            const Divider(height: 40),
            Text(
              'RM ${booking.amount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text('Payment status: ${booking.paymentStatus}'),
            if (_testMode)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Test payment mode: use only the gateway test payment details. No real payment will be taken.',
                ),
              ),
            const SizedBox(height: 24),
            if (booking.hasReceipt) ...[
              const Text('Payment has been recorded by the server.'),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => CustomerReceiptScreen(
                      bookingId: booking.id,
                      transactions: _transactions,
                    ),
                  ),
                ),
                child: const Text('View receipt'),
              ),
            ] else if (booking.canPay) ...[
              const Text(
                'Choose your payment method on the secure gateway page. Return here afterwards to check the result.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _processing || _loading ? null : _pay,
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  _processing ? 'Opening payment…' : 'Open secure payment',
                ),
              ),
            ] else
              const Text(
                'Payment is not available for the current booking status.',
              ),
            if (_openedGateway && !booking.hasReceipt) ...[
              const SizedBox(height: 24),
              const Text(
                'Closing the gateway does not confirm payment. Confirmation may take a moment. You can also check this booking later from My bookings.',
              ),
              OutlinedButton(
                onPressed: _loading || _processing ? null : _refresh,
                child: const Text('Check payment status'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
