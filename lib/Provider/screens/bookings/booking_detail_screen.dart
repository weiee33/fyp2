import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import 'chat_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});
  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final _service = BookingService();
  Map<String, dynamic>? _b;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _b = await _service.getBookingDetail(widget.bookingId);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _update(String status) async {
    await _service.updateStatus(widget.bookingId, status);
    _load();
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const TextField(
          decoration: InputDecoration(hintText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'Cancelled by provider'),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (reason != null) {
      await _service.cancel(widget.bookingId, reason);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking Detail')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _b == null
              ? const Center(child: Text('Booking not found'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    children: [
                      _row('Customer',
                          _b!['customer_profiles']?['users']?['full_name'] ?? '-'),
                      _row('Contact',
                          _b!['customer_profiles']?['users']?['phone'] ?? '-'),
                      _row('Service', _b!['services']?['service_name'] ?? '-'),
                      _row('Date',
                          '${_b!['booking_date']} ${_b!['scheduled_time']}'),
                      _row('Address', _b!['customer_address'] ?? '-'),
                      _row('Payment',
                          'RM${_b!['total_amount']} · ${_b!['booking_status']}'),
                      const SizedBox(height: 12),
                      if (_b!['special_instructions'] != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                                'Special Instructions: ${_b!['special_instructions']}'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_b!['booking_status'] == 'Pending')
                            ElevatedButton(
                                onPressed: () => _update('Confirmed'),
                                child: const Text('Accept')),
                          if (_b!['booking_status'] == 'Pending')
                            OutlinedButton(
                                onPressed: _cancel,
                                child: const Text('Decline')),
                          if (_b!['booking_status'] == 'Confirmed')
                            ElevatedButton(
                                onPressed: () => _update('In-Progress'),
                                child: const Text('Start Service')),
                          if (_b!['booking_status'] == 'In-Progress')
                            ElevatedButton(
                                onPressed: () => _update('Completed'),
                                child: const Text('Complete Service')),
                          OutlinedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                    bookingId: widget.bookingId),
                              ),
                            ),
                            child: const Text('Chat'),
                          ),
                          if (_b!['booking_status'] != 'Cancelled' &&
                              _b!['booking_status'] != 'Completed')
                            TextButton(
                              onPressed: _cancel,
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              child: const Text('Cancel Booking'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 90,
                child: Text(label,
                    style: const TextStyle(color: Colors.grey))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );
}