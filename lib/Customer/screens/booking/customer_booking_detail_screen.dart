import '../../agent/agent_surface.dart';
import '../support/customer_support_screen.dart';
import '../../services/customer_support_service.dart';
import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/booking_status.dart';
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
  final CustomerSupportService? supportService;
  const CustomerBookingDetailScreen({
    super.key,
    required this.bookingId,
    this.transactions,
    this.supportService,
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
          title: tr('Unable to complete'),
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Cancel booking?')),
        content: TextField(
          controller: reason,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(labelText: trOrNull('Reason (optional)')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Keep booking')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CustomerTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Cancel Booking')),
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
        await CustomerDialogs.show(context, message: tr('Booking cancelled.'));
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
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSupportComposeScreen(
          bookingId: widget.bookingId,
          booking: _booking,
          service: widget.supportService,
        ),
      ),
    );
    if (!mounted || id == null) return;
    await _load();
    if (mounted)
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerSupportDetailScreen(
            id: id,
            service: widget.supportService ?? CustomerSupportService(),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final booking = _booking;
    return CustomerScaffold(
      agentScreen: 'booking_detail',
      agentReady: !_loading && !_acting,
      appBar: AppBar(
        leading: BackButton().agent('Back'),
        title: Text(tr('Booking Details')),
        actions: [
          IconButton(
            tooltip: trOrNull('Chat with provider'),
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
                physics: customerScrollPhysics(context),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(tr(_error!)),
                    TextButton(onPressed: _load, child: Text(tr('Try again'))),
                  ],
                  if (_loading) const LinearProgressIndicator(),
                  if (booking != null) ...[
                    BookingSection(
                      title: tr('Your booking'),
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
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              key: const ValueKey('booking-status'),
                              constraints: const BoxConstraints(minHeight: 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(tr(booking.displayStatus)),
                            ),
                            BookingPaymentStatus(
                              booking: booking,
                              minHeight: 40,
                            ),
                          ],
                        ),
                        Text(
                          tr("Booking {0}", [booking.shortId]),
                          style: const TextStyle(
                            color: CustomerTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    BookingSection(
                      title: _nextStepTitle(booking),
                      icon: booking.paymentStatus == 'Success'
                          ? Icons.check_circle
                          : booking.needsNewBooking
                          ? Icons.cancel
                          : Icons.info_outline,
                      accentColor: booking.paymentStatus == 'Success'
                          ? const Color(0xFF157347)
                          : booking.needsNewBooking
                          ? const Color(0xFFB42318)
                          : null,
                      children: [
                        Text(tr(_nextStepMessage(booking))),
                        if (booking.canPay &&
                            booking.paymentDeadline != null) ...[
                          const SizedBox(height: 10),
                          PaymentCountdown(deadline: booking.paymentDeadline!),
                          const SizedBox(height: 10),
                          Text(
                            tr("Pay by {0} (Malaysia time)", [
                              DateFormat.MMMd().add_jm().format(
                                booking.paymentDeadline!.toUtc().add(
                                  const Duration(hours: 8),
                                ),
                              ),
                            ]),
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
                              label: Text(tr('Choose a new appointment')),
                            ),
                          ),
                        ],
                      ],
                    ),
                    BookingSection(
                      title: tr('Your service journey'),
                      icon: Icons.route_outlined,
                      children: [BookingProgress(booking: booking)],
                    ),
                    BookingSection(
                      title: tr('Appointment & location'),
                      icon: Icons.event_outlined,
                      children: [
                        _row(
                          'Appointment',
                          tr("{0}\nMalaysia time", [booking.appointmentLabel]),
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
                      title: tr('Payment summary'),
                      icon: Icons.receipt_long_outlined,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(tr('Service total'))),
                            Text(
                              tr('RM ${booking.amount.toStringAsFixed(2)}'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: CustomerTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            BookingPaymentStatus(
                              booking: booking,
                              minHeight: 40,
                            ),
                            if (booking.hasReceipt)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _acting
                                    ? null
                                    : () => _open(
                                        CustomerReceiptScreen(
                                          bookingId: booking.id,
                                          transactions: _transactions,
                                        ),
                                      ),
                                icon: const Icon(Icons.receipt_long),
                                label: Text(tr('View Receipt')),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (!booking.hasReview &&
                        !booking.canReview &&
                        booking.paymentStatus == 'Success')
                      BookingSection(
                        title: tr('Review your service'),
                        icon: Icons.rate_review_outlined,
                        children: [
                          Text(
                            tr(
                              booking.status == 'Cancelled'
                                  ? 'Reviews are available for completed services. Contact support about this cancelled booking.'
                                  : 'Your payment is confirmed. You can write a review here once the provider marks your service Completed.',
                            ),
                          ),
                        ],
                      ),
                    if (booking.hasReview)
                      ListTile(
                        leading: Icon(Icons.rate_review_outlined),
                        title: Text(tr('Your review has been submitted.')),
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
                        label: Text(tr('Write a review')),
                      ),
                    BookingSection(
                      title: tr('Help with this booking'),
                      icon: Icons.support_agent,
                      children: [
                        for (final dispute
                            in (booking.data['disputes'] as List? ?? []))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(dispute['subject'].toString()),
                            subtitle: Text(
                              '${tr(dispute['status'].toString())}\n${dispute['resolution'] ?? tr('Awaiting administrator review.')}',
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: CustomerTheme.actionStyle(outlined: true),
                            onPressed: _acting || _loading
                                ? null
                                : _requestHelp,
                            icon: const Icon(Icons.support_agent),
                            label: Text(
                              tr('Request Booking Support'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        if (booking.canCancel && !booking.needsNewBooking) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: CustomerTheme.actionStyle(
                              outlined: true,
                              destructive: true,
                            ),
                            onPressed: _acting || _loading ? null : _cancel,
                            icon: const Icon(Icons.event_busy_outlined),
                            label: Text(
                              tr(_acting ? 'Cancelling…' : 'Cancel Booking'),
                            ),
                          ),
                        ],
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
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(tr('Continue to payment')),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  String _nextStepTitle(CustomerBooking booking) {
    if (booking.hasReceipt &&
        booking.status == 'Cancelled' &&
        booking.paymentStatus != 'Refunded') {
      return 'Payment received · Booking cancelled';
    }
    if (booking.hasReceipt) {
      return booking.paymentStatus == 'Refunded'
          ? 'Payment refunded'
          : 'Payment received';
    }
    if (booking.needsNewBooking) return 'Payment is no longer available';
    if (booking.canPay) return 'Provider accepted your booking';
    if (booking.status == 'Pending') return 'Waiting for provider acceptance';
    if (booking.status == 'Cancelled') return 'Booking cancelled';
    return 'Booking status';
  }

  String _nextStepMessage(CustomerBooking booking) {
    if (booking.hasReceipt &&
        booking.status == 'Cancelled' &&
        booking.paymentStatus != 'Refunded') {
      return 'Your payment is recorded, but this appointment is cancelled. Check the support request below for refund review. Do not pay again.';
    }
    if (booking.hasReceipt) {
      return 'View your receipt below for the verified payment record.';
    }
    if (booking.needsNewBooking) {
      return 'This unpaid reservation has expired. The request or payment deadline has passed, or the appointment time is already over. Choose a new available appointment to book again.';
    }
    if (booking.canPay) {
      return 'Next: pay by FPX, card or GrabPay to keep your appointment. Use the payment button below. Availability is checked again before checkout.';
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
        tr(label),
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
