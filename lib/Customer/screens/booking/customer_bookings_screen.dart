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
    if (_transactions.usesLiveBackend)
      _updates = CustomerLiveUpdates(() => _load(reset: true));
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
      if (mounted)
        setState(() {
          if (reset) _bookings.clear();
          _bookings.addAll(rows);
          _hasMore = rows.length == 20;
        });
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
      actions: [
        IconButton(
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh bookings',
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
              child: ListTile(
                isThreeLine: true,
                title: Text(booking.serviceName),
                subtitle: Text(
                  '${booking.providerName}\n${booking.date} · ${booking.time}\n${booking.status} · ${booking.paymentStatus}',
                ),
                trailing: const Icon(Icons.chevron_right),
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
