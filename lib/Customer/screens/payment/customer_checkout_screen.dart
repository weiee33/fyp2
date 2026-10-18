import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/booking_status.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/customer_theme.dart';
import '../../widgets/booking_section.dart';
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
  String? _checkoutError, _statusError;
  bool _setupRequired = false,
      _loading = false,
      _processing = false,
      _openedGateway = false;
  bool _foreground = true;
  String _paymentOption = 'fpx';
  Timer? _poll, _deadline;
  int _pollsRemaining = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _deadline?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _poll?.cancel();
      return;
    }
    if (_openedGateway) {
      _pollsRemaining = 12;
      _refresh();
    }
  }

  void _scheduleCheck() {
    _poll?.cancel();
    if (!_foreground ||
        !_openedGateway ||
        _booking?.hasReceipt == true ||
        _pollsRemaining <= 0) {
      return;
    }
    _poll = Timer(const Duration(seconds: 5), () {
      _pollsRemaining--;
      _refresh();
    });
  }

  Future<void> _refresh() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _statusError = null;
    });
    try {
      final booking = await _transactions.getBooking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        final channel = booking.data['checkout_channel'];
        if (channel == 'fpx' || channel == 'wallet_card') {
          _paymentOption = channel as String;
        }
        if (booking.hasReceipt) {
          _checkoutError = null;
          _setupRequired = false;
        }
      });
      _deadline?.cancel();
      if (booking.canPay && booking.paymentDeadline != null) {
        _deadline = Timer(
          booking.paymentDeadline!.difference(DateTime.now()),
          () {
            if (mounted) setState(() {});
          },
        );
      }
    } catch (error) {
      if (mounted) setState(() => _statusError = bookingError(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scheduleCheck();
      }
    }
  }

  Future<void> _pay() async {
    if (_processing || _loading || _booking?.canPay != true) return;
    setState(() {
      _processing = true;
      _checkoutError = null;
      _setupRequired = false;
    });
    try {
      final session = await _transactions.startCheckout(
        widget.bookingId,
        paymentOption: _paymentOption,
      );
      if (!mounted) return;
      final launched =
          await (widget.launchCheckout?.call(session.url) ??
              launchUrl(session.url, mode: LaunchMode.externalApplication));
      if (!mounted) return;
      if (!launched) {
        setState(
          () => _checkoutError =
              'The secure payment page could not open. Please try again.',
        );
      } else {
        setState(() => _openedGateway = true);
        _pollsRemaining = 12;
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _checkoutError = bookingError(error);
          _setupRequired = checkoutSetupRequired(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        await _refresh();
      }
    }
  }

  void _receipt() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CustomerReceiptScreen(
          bookingId: widget.bookingId,
          transactions: _transactions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final booking = _booking;
    final paid = booking?.hasReceipt == true;
    final refunded = booking?.paymentStatus == 'Refunded';
    final receiptColor = refunded
        ? const Color(0xFF5F6368)
        : const Color(0xFF157347);
    final busy = _loading || _processing;
    final methodLocked =
        _openedGateway || booking?.data['checkout_channel'] != null;
    final accepted =
        booking != null &&
        (booking.data['accepted_at'] != null ||
            [
              'Confirmed',
              'In Progress',
              'Completed',
            ].contains(booking.status) ||
            paid);
    final error = _checkoutError ?? _statusError;
    return CustomerScaffold(
      appBar: AppBar(title: Text(tr('Payment'))),
      body: booking == null && _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  BookingSection(
                    title: tr(
                      _setupRequired
                          ? 'Payment unavailable'
                          : _checkoutError != null
                          ? 'Could not open payment'
                          : 'Could not check payment status',
                    ),
                    icon: Icons.info_outline,
                    highlighted: true,
                    children: [
                      Text(tr(error)),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          _setupRequired
                              ? 'No new checkout was opened. You can try again once the service is available.'
                              : 'Your booking is not marked paid unless the payment server confirms it.',
                        ),
                      ),
                      if (_statusError != null)
                        TextButton(
                          onPressed: busy ? null : _refresh,
                          child: Text(tr('Refresh status')),
                        ),
                    ],
                  ),
                if (paid)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: .7, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 450),
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          Icon(
                            refunded ? Icons.undo_rounded : Icons.check_circle,
                            size: 64,
                            color: receiptColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              refunded
                                  ? 'Payment refunded'
                                  : 'Payment confirmed',
                            ),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(tr('Your receipt is ready below.')),
                        ],
                      ),
                    ),
                  ),
                if (booking?.canPay == true && booking?.paymentDeadline != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: PaymentCountdown(
                      deadline: booking!.paymentDeadline!,
                    ),
                  ),
                if (!paid && booking?.canPay == true)
                  BookingSection(
                    title: tr('Payment method'),
                    icon: Icons.account_balance_wallet_outlined,
                    children: [
                      RadioGroup<String>(
                        groupValue: _paymentOption,
                        onChanged: (value) {
                          if (!busy && !methodLocked && value != null) {
                            setState(() => _paymentOption = value);
                          }
                        },
                        child: Column(
                          children: [
                            RadioListTile<String>(
                              value: 'fpx',
                              enabled: !busy && !methodLocked,
                              title: Text(tr('FPX online banking')),
                              subtitle: Text(tr('Choose your Malaysian bank')),
                            ),
                            RadioListTile<String>(
                              value: 'wallet_card',
                              enabled: !busy && !methodLocked,
                              title: Text(tr('Debit / credit card or GrabPay')),
                              subtitle: Text(
                                tr('Choose on the secure Stripe page'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        tr(
                          'Card number, expiry and CVC are validated by Stripe. Your card details are never stored in this app.',
                        ),
                        style: TextStyle(fontSize: 12),
                      ),
                      if (methodLocked)
                        Text(
                          tr(
                            'Continue the opened checkout. Its payment option is reserved until the window ends.',
                          ),
                          style: TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                BookingSection(
                  title: tr('Your payment journey'),
                  icon: Icons.route_outlined,
                  children: [
                    _step(
                      1,
                      'Provider acceptance',
                      accepted
                          ? 'Your requested appointment was accepted.'
                          : 'Waiting for the provider to accept your request.',
                      done: accepted,
                      current: !accepted,
                    ),
                    _step(
                      2,
                      'Secure payment',
                      paid
                          ? 'Payment recorded.'
                          : _openedGateway
                          ? 'Complete the secure payment page, then return here. Opening it does not mean payment succeeded.'
                          : 'Choose FPX online banking, or cards and GrabPay. Payment details are entered securely on Stripe.',
                      done: paid,
                      current: accepted && !paid,
                    ),
                    _step(
                      3,
                      refunded ? 'Refund recorded' : 'Payment confirmation',
                      refunded
                          ? 'The payment was refunded. Your updated receipt is ready.'
                          : paid
                          ? 'Verified by the payment server. Your receipt is ready.'
                          : 'Your receipt appears only after the payment result is verified.',
                      done: paid,
                      current: false,
                      last: true,
                    ),
                  ],
                ),
                if (booking != null) ...[
                  BookingSection(
                    accentColor: paid ? receiptColor : null,
                    title: tr(
                      paid
                          ? (booking.paymentStatus == 'Refunded'
                                ? 'Payment refunded'
                                : 'Payment confirmed')
                          : 'Payment summary',
                    ),
                    icon: refunded
                        ? Icons.undo_rounded
                        : paid
                        ? Icons.verified_outlined
                        : Icons.receipt_long_outlined,
                    highlighted: true,
                    children: [
                      Text(
                        booking.serviceName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(booking.providerName),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Text(tr('Total'))),
                          Text(
                            tr('RM ${booking.amount.toStringAsFixed(2)}'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              color: CustomerTheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(tr("Payment status: {0}", [booking.paymentStatus])),
                      if (booking.canPay && booking.paymentDeadline != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            tr("Pay by {0} (Malaysia time)", [
                              DateFormat.MMMd().add_jm().format(
                                booking.paymentDeadline!.toUtc().add(
                                  const Duration(hours: 8),
                                ),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ),
                  if (_openedGateway && !paid)
                    BookingSection(
                      title: tr('Waiting for the payment result'),
                      icon: Icons.schedule,
                      children: [
                        Text(
                          tr(
                            'Return here after completing the secure payment page. We check for confirmation automatically for one minute. Closing that page alone does not confirm payment.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () {
                                  _pollsRemaining = 12;
                                  _refresh();
                                },
                          child: Text(tr('Check payment status')),
                        ),
                      ],
                    ),
                  if (!paid && !booking.canPay)
                    BookingSection(
                      title: tr(
                        booking.needsNewBooking
                            ? 'Payment window ended'
                            : 'Payment not available yet',
                      ),
                      icon: Icons.event_busy_outlined,
                      children: [
                        Text(
                          tr(
                            booking.needsNewBooking
                                ? 'This unpaid reservation expired. Return to Booking details to choose a new appointment. If you already completed the secure payment page, check the payment status before starting another booking.'
                                : 'Return to Booking details to check the provider response and booking status.',
                          ),
                        ),
                      ],
                    ),
                  BookingSection(
                    title: tr('Appointment'),
                    icon: Icons.event_outlined,
                    children: [
                      Text(
                        tr("{0} (Malaysia time)", [booking.appointmentLabel]),
                      ),
                      const SizedBox(height: 10),
                      Text(booking.address),
                    ],
                  ),
                ],
              ],
            ),
      bottomNavigationBar: booking == null
          ? null
          : Material(
              color: Colors.white,
              elevation: 4,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : paid
                          ? _receipt
                          : booking.canPay
                          ? _pay
                          : () => Navigator.maybePop(context),
                      icon: Icon(
                        paid
                            ? Icons.receipt_long
                            : booking.canPay
                            ? Icons.open_in_new
                            : Icons.arrow_back,
                      ),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          tr(
                            paid
                                ? 'View Receipt'
                                : _processing
                                ? 'Opening payment…'
                                : booking.canPay
                                ? (_openedGateway
                                      ? 'Reopen secure payment'
                                      : 'Open secure payment')
                                : 'Back to booking',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _step(
    int number,
    String title,
    String subtitle, {
    required bool done,
    required bool current,
    bool last = false,
  }) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: done
              ? CustomerTheme.success
              : current
              ? CustomerTheme.primary
              : CustomerTheme.borderColor,
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 19)
              : Text(
                  tr('$number'),
                  style: TextStyle(
                    color: current ? Colors.white : CustomerTheme.textSecondary,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(title),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                tr(subtitle),
                style: const TextStyle(
                  fontSize: 13,
                  color: CustomerTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
