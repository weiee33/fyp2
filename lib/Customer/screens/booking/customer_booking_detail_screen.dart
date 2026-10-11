import 'dart:async';
import 'package:intl/intl.dart';
import '../../widgets/booking_section.dart';
import '../../core/customer_theme.dart';
import '../browsing/customer_provider_detail_screen.dart';
import '../../services/customer_notification_service.dart';
import '../../widgets/customer_unread_badge.dart';
import '../../widgets/customer_refresh.dart';
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
  Timer? _deadlineTimer;
  @override
  void initState() {
    super.initState();
    _load();
    if (_transactions.usesLiveBackend) _updates = CustomerLiveUpdates(_load);
  }

  @override
  void dispose() {
    _updates?.dispose();
    _deadlineTimer?.cancel();
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
      if (mounted) {
        setState(() => _booking = booking);
        _deadlineTimer?.cancel();
        final deadline = booking.paymentDeadline;
        if (booking.canPay && deadline != null) {
          _deadlineTimer = Timer(deadline.difference(DateTime.now()), () {
            if (mounted) setState(() {});
          });
        }
      }
      if (mounted &&
          _transactions.usesLiveBackend &&
          ModalRoute.of(context)?.isCurrent == true) {
        try {
          await CustomerNotificationService().markBookingRead(widget.bookingId);
          await CustomerActivityCounts.shared.refresh();
        } catch (_) {
          /* Realtime/reopen retries acknowledgement. */
        }
      }
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
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
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
        ],
      ),
      body: _loading && booking == null
          ? const Center(child: CircularProgressIndicator())
          : CustomerRefresh(
              onRefresh: _load,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.all(16),
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
                    BookingSection(
                      title: 'Your booking',
                      icon: Icons.home_repair_service_outlined,
                      highlighted: true,
                      children: [
                        Text(
                          booking.serviceName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(booking.providerName),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Chip(label: Text(booking.displayStatus)),
                            Chip(label: Text(booking.paymentStatus)),
                          ],
                        ),
                        Text(
                          'Booking ${booking.shortId}',
                          style: const TextStyle(
                            color: CustomerTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    BookingSection(
                      title: _nextStepTitle(booking),
                      icon: Icons.info_outline,
                      children: [
                        Text(_nextStepMessage(booking)),
                        if (booking.canPay &&
                            booking.paymentDeadline != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Pay by ${DateFormat('d MMM, h:mm a').format(booking.paymentDeadline!.toUtc().add(const Duration(hours: 8)))} (Malaysia time)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: CustomerTheme.primary,
                            ),
                          ),
                        ],
                        if (booking.needsNewBooking) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _acting || _loading
                                  ? null
                                  : () => _open(
                                      CustomerProviderDetailScreen(
                                        providerId: booking.providerId,
                                        heroTag: 'rebook-${booking.id}',
                                        selectedServiceId: booking
                                            .data['service_id']
                                            ?.toString(),
                                      ),
                                    ),
                              icon: const Icon(Icons.event_available),
                              label: const Text('Choose a new appointment'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    BookingSection(
                      title: 'Appointment & location',
                      icon: Icons.event_outlined,
                      children: [
                        _row(
                          'Appointment',
                          '${booking.date} · ${booking.time}\nMalaysia time',
                        ),
                        const Divider(height: 24),
                        _row('Service address', booking.address),
                        if ((booking.data['special_instructions']?.toString() ??
                                '')
                            .isNotEmpty) ...[
                          const Divider(height: 24),
                          _row(
                            'Your instructions',
                            booking.data['special_instructions'].toString(),
                          ),
                        ],
                      ],
                    ),
                    BookingSection(
                      title: 'Payment summary',
                      icon: Icons.receipt_long_outlined,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('Service total')),
                            Text(
                              'RM ${booking.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: CustomerTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('Payment status: ${booking.paymentStatus}'),
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
                      ],
                    ),
                    if (booking.hasReview)
                      const ListTile(
                        leading: Icon(Icons.rate_review_outlined),
                        title: Text('Your review has been submitted.'),
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
                    BookingSection(
                      title: 'Help with this booking',
                      icon: Icons.support_agent,
                      children: [
                        for (final dispute
                            in (booking.data['disputes'] as List? ?? []))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(dispute['subject'].toString()),
                            subtitle: Text(
                              '${dispute['status']}\n${dispute['resolution'] ?? 'Awaiting administrator review.'}',
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _acting || _loading
                                ? null
                                : _requestHelp,
                            icon: const Icon(Icons.support_agent),
                            label: const Text('Request booking support'),
                          ),
                        ),
                        if (booking.canCancel && !booking.needsNewBooking)
                          TextButton(
                            onPressed: _acting || _loading ? null : _cancel,
                            child: Text(
                              _acting ? 'Cancelling…' : 'Cancel booking',
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: booking?.canPay == true
          ? Material(
              color: Colors.white,
              elevation: 6,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _acting || _loading
                        ? null
                        : () => _open(
                            CustomerCheckoutScreen(
                              bookingId: booking!.id,
                              transactions: _transactions,
                            ),
                          ),
                    icon: const Icon(Icons.payment),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Continue to payment'),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  String _nextStepTitle(CustomerBooking booking) {
    if (booking.hasReceipt) {
      return booking.paymentStatus == 'Refunded'
          ? 'Payment refunded'
          : 'Payment received';
    }
    if (booking.needsNewBooking) return 'Payment is no longer available';
    if (booking.canPay) return 'Your slot is accepted — pay by FPX';
    if (booking.status == 'Pending') return 'Waiting for provider acceptance';
    if (booking.status == 'Cancelled') return 'Booking cancelled';
    return 'Booking status';
  }

  String _nextStepMessage(CustomerBooking booking) {
    if (booking.hasReceipt) {
      return 'View your receipt below for the verified payment record.';
    }
    if (booking.needsNewBooking) {
      return 'This unpaid reservation has expired. The request or payment deadline has passed, or the appointment time is already over. Choose a new available appointment to book again.';
    }
    if (booking.canPay) {
      return 'Complete secure FPX payment to keep your appointment. Use the payment button below. Availability is checked again before checkout.';
    }
    if (booking.status == 'Pending') {
      return 'Your request has been sent. Once the provider accepts, you have 30 minutes to pay. We will notify you when payment is available.';
    }
    if (booking.status == 'Cancelled') {
      return 'This booking is cancelled and cannot be paid.';
    }
    return 'Payment is not available for this booking. Refresh to check its latest status, or request booking support below.';
  }

  Widget _row(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: CustomerTheme.textSecondary,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontSize: 15, height: 1.5)),
    ],
  );
}
