import '../../../shared/chat/chat_screen.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../models/booking_model.dart';
import '../../services/customer_transaction_service.dart';
import '../../services/customer_live_updates.dart';
import '../payment/customer_checkout_screen.dart';
import '../payment/customer_receipt_screen.dart';
import '../review/customer_submit_review_screen.dart';

class CustomerBookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final CustomerTransactionService? transactions;
  const CustomerBookingDetailScreen({
    super.key,
    required this.bookingId,
    this.transactions,
  });
  @override
  State<CustomerBookingDetailScreen> createState() =>
      _CustomerBookingDetailScreenState();
}

class _CustomerBookingDetailScreenState
    extends State<CustomerBookingDetailScreen> {
  late final CustomerTransactionService _transactions =
      widget.transactions ?? CustomerTransactionService();
  CustomerBooking? _booking;
  String? _error;
  bool _loading = true;
  bool _acting = false;
  CustomerLiveUpdates? _updates;
  @override
  void initState() {
    super.initState();
    _load();
    if (_transactions.usesLiveBackend) _updates = CustomerLiveUpdates(_load);
  }

  @override
  void dispose() {
    _updates?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
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

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: TextField(
          controller: reason,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    // Dispose after the dialog's reverse transition releases the text field.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    reason.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _acting = true);
    try {
      final booking = await _transactions.cancelBooking(widget.bookingId, text);
      if (mounted) {
        setState(() {
          _booking = booking;
          _acting = false;
        });
        await CustomerDialogs.show(context, message: 'Booking cancelled.');
      }
    } catch (error) {
      if (mounted) CustomerDialogs.show(context, message: bookingError(error));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  Future<void> _requestHelp() async {
    final subject = TextEditingController();
    final description = TextEditingController();
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request booking support'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: subject,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: (value) => (value?.trim().length ?? 0) >= 3
                      ? null
                      : 'Enter at least 3 characters',
                ),
                TextFormField(
                  controller: description,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Describe the problem',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) >= 10
                      ? null
                      : 'Enter at least 10 characters',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    final title = subject.text.trim(), message = description.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    subject.dispose();
    description.dispose();
    if (!mounted || confirmed != true) return;
    setState(() => _acting = true);
    try {
      await _transactions.requestSupport(widget.bookingId, title, message);
      if (mounted) {
        setState(() => _acting = false);
        await CustomerDialogs.show(
          context,
          message: 'Your support request has been submitted.',
        );
      }
      if (mounted) await _load();
    } catch (error) {
      if (mounted) CustomerDialogs.show(context, message: bookingError(error));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking details'),
        actions: [
          IconButton(
            tooltip: 'Chat with provider',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConversationScreen(bookingId: widget.bookingId),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
          ),

          IconButton(
            onPressed: _loading || _acting ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh booking',
          ),
        ],
      ),
      body: _loading && booking == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null) ...[
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                  if (_loading) const LinearProgressIndicator(),
                  if (booking != null) ...[
                    Text(
                      booking.serviceName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(booking.providerName),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(label: Text(booking.status)),
                        Chip(label: Text(booking.paymentStatus)),
                      ],
                    ),
                    _row('Booking', booking.shortId),
                    _row(
                      'Appointment',
                      '${booking.date}\n${booking.time} (Malaysia time)',
                    ),
                    _row('Address', booking.address),
                    _row('Total', 'RM ${booking.amount.toStringAsFixed(2)}'),
                    if ((booking.data['special_instructions']?.toString() ?? '')
                        .isNotEmpty)
                      _row(
                        'Instructions',
                        booking.data['special_instructions'].toString(),
                      ),
                    if (booking.data['reservation_expires_at'] != null &&
                        booking.canPay)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Complete payment before your reservation expires. Availability is checked again before checkout.',
                        ),
                      ),
                    if (booking.status == 'Pending')
                      const Text(
                        'Waiting for the provider to accept your requested slot. Payment becomes available after acceptance.',
                      ),
                    if (booking.data['reservation_expired'] == true)
                      const Text(
                        'This request or payment window has expired. Please choose a new available slot.',
                      ),
                    if (booking.hasReview)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.rate_review_outlined),
                        title: Text('Your review has been submitted.'),
                      ),
                    const SizedBox(height: 20),
                    if (booking.canPay)
                      FilledButton.icon(
                        onPressed: _acting || _loading
                            ? null
                            : () => _open(
                                CustomerCheckoutScreen(
                                  bookingId: booking.id,
                                  transactions: _transactions,
                                ),
                              ),
                        icon: const Icon(Icons.payment),
                        label: const Text('Continue to payment'),
                      ),
                    if (booking.hasReceipt)
                      OutlinedButton.icon(
                        onPressed: _acting
                            ? null
                            : () => _open(
                                CustomerReceiptScreen(
                                  bookingId: booking.id,
                                  transactions: _transactions,
                                ),
                              ),
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('View receipt'),
                      ),
                    if (booking.canReview)
                      FilledButton.icon(
                        onPressed: _acting
                            ? null
                            : () => _open(
                                CustomerSubmitReviewScreen(
                                  bookingId: booking.id,
                                  providerId: booking.providerId,
                                  providerName: booking.providerName,
                                  serviceName: booking.serviceName,
                                ),
                              ),
                        icon: const Icon(Icons.star_outline),
                        label: const Text('Write a review'),
                      ),
                    if (booking.canCancel)
                      TextButton(
                        onPressed: _acting || _loading ? null : _cancel,
                        child: Text(_acting ? 'Cancelling…' : 'Cancel booking'),
                      ),
                    for (final dispute
                        in (booking.data['disputes'] as List? ?? []))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(dispute['subject'].toString()),
                        subtitle: Text(
                          '${dispute['status']}\n${dispute['resolution'] ?? 'Awaiting administrator review.'}',
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _acting || _loading ? null : _requestHelp,
                      icon: const Icon(Icons.support_agent),
                      label: const Text('Request booking support'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16)),
      ],
    ),
  );
}
