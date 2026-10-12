import '../../widgets/booking_status.dart';
import '../../widgets/customer_unread_badge.dart';
import '../../widgets/customer_refresh.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../models/booking_model.dart';
import '../../services/customer_transaction_service.dart';
import '../../services/customer_live_updates.dart';
import 'customer_booking_detail_screen.dart';

class CustomerBookingsScreen extends StatefulWidget {
  final CustomerTransactionService? transactions;
  const CustomerBookingsScreen({super.key, this.transactions});
  @override
  State<CustomerBookingsScreen> createState() => _CustomerBookingsScreenState();
}

class _CustomerBookingsScreenState extends State<CustomerBookingsScreen> {
  late final CustomerTransactionService _transactions =
      widget.transactions ?? CustomerTransactionService();
  final List<CustomerBooking> _bookings = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  CustomerLiveUpdates? _updates;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
    if (_transactions.usesLiveBackend) {
      _updates = CustomerLiveUpdates(() => _load(reset: true));
    }
  }

  @override
  void dispose() {
    _updates?.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _transactions.getBookings(
        offset: reset ? 0 : _bookings.length,
      );
      if (mounted) {
        setState(() {
          if (reset) _bookings.clear();
          _bookings.addAll(rows);
          _hasMore = rows.length == 20;
        });
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My bookings'),
      actions: [CustomerChatButton(enabled: _transactions.usesLiveBackend)],
    ),
    body: CustomerRefresh(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading && _bookings.isEmpty)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: () => _load(reset: _bookings.isEmpty),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && _error == null && _bookings.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No bookings yet. Find a service from Home to get started.',
                textAlign: TextAlign.center,
              ),
            ),
          ..._bookings.map(
            (booking) => Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: booking.paymentStatus == 'Success'
                      ? const Color(0xFFB7DFC8)
                      : booking.displayStatus == 'Expired'
                      ? const Color(0xFFF0C2BD)
                      : const Color(0xFFE2E5EA),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CustomerBookingDetailScreen(
                        bookingId: booking.id,
                        transactions: _transactions,
                      ),
                    ),
                  );
                  if (mounted) await _load(reset: true);
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              booking.serviceName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        booking.providerName,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      Text(booking.appointmentLabel),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          BookingPaymentStatus(booking: booking),
                          if (booking.canReview)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.star_outline,
                                    size: 18,
                                    color: Color(0xFFFF6B00),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Ready to review',
                                    style: TextStyle(
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            booking.displayStatus,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_bookings.isNotEmpty && _hasMore)
            TextButton(
              onPressed: _loading ? null : _load,
              child: Text(_loading ? 'Loading…' : 'Load more'),
            ),
        ],
      ),
    ),
  );
}
