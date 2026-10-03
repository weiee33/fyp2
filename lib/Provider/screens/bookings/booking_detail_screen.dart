import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import '../../../Customer/services/customer_transaction_service.dart'
    show bookingError;

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
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final booking = await _service.getBookingDetail(widget.bookingId);
      if (mounted)
        setState(() {
          _b = booking;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = bookingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(String status) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await _service.updateStatus(widget.bookingId, status);
      if (mounted) await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(bookingError(error))));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline booking request'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Reason (at least 3 characters)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().length >= 3)
                Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (reason != null && mounted && !_acting) {
      setState(() => _acting = true);
      try {
        await _service.cancel(widget.bookingId, reason);
        if (mounted) await _load();
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(bookingError(error))));
      } finally {
        if (mounted) setState(() => _acting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Detail'),
        actions: [
          IconButton(
            onPressed: _loading || _acting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _b == null
          ? Center(child: Text(_error ?? 'Booking not found'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  if (_error != null) Text(_error!),
                  _row(
                    'Customer',
                    _b!['customer_profiles']?['users']?['full_name'] ?? '-',
                  ),
                  _row(
                    'Contact',
                    _b!['customer_profiles']?['users']?['phone'] ?? '-',
                  ),
                  _row('Service', _b!['services']?['service_name'] ?? '-'),
                  _row(
                    'Date',
                    '${_b!['booking_date']} ${_b!['scheduled_time']}',
                  ),
                  _row('Address', _b!['customer_address'] ?? '-'),
                  _row(
                    'Payment',
                    'RM${_b!['total_amount']} · ${_b!['payment_status'] ?? 'Not paid'}',
                  ),
                  _row('Status', _b!['booking_status'] ?? '-'),
                  if (_b!['booking_status'] == 'Confirmed' &&
                      _b!['payment_status'] != 'Success')
                    const Text(
                      'Slot accepted. Waiting for the customer to complete FPX payment.',
                    ),
                  const SizedBox(height: 12),
                  if (_b!['special_instructions'] != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Special Instructions: ${_b!['special_instructions']}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_b!['can_accept'] == true)
                        ElevatedButton(
                          onPressed: _acting
                              ? null
                              : () => _update('Confirmed'),
                          child: const Text('Accept'),
                        ),
                      if (_b!['can_accept'] == true)
                        OutlinedButton(
                          onPressed: _acting ? null : _cancel,
                          child: const Text('Decline'),
                        ),
                      if (_b!['can_start'] == true)
                        ElevatedButton(
                          onPressed: _acting
                              ? null
                              : () => _update('In-Progress'),
                          child: const Text('Start Service'),
                        ),
                      if (_b!['booking_status'] == 'In-Progress')
                        ElevatedButton(
                          onPressed: _acting
                              ? null
                              : () => _update('Completed'),
                          child: const Text('Complete Service'),
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
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}
