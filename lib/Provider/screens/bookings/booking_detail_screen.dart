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

  static const _primaryColor = Color(0xFFF97316); // Orange
  static const _accentColor = Color(0xFFFFF7ED); // Light orange tint

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bookingError(error)),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  // ========== Cancel with Validation ==========
  Future<void> _cancel() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Decline booking request',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            maxLength: 500,
            maxLines: 4,
            minLines: 3,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Reason is required';
              if (text.length < 3) {
                return 'Reason must be at least 3 characters';
              }
              if (text.length > 500) {
                return 'Reason must not exceed 500 characters';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: 'Please provide a reason...',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: _primaryColor,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
            ),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(bookingError(error)),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
      } finally {
        if (mounted) setState(() => _acting = false);
      }
    }
  }

  // ========== Status Badge ==========
  Color _statusColor(String? status) {
    switch (status) {
      case 'Pending':
        return const Color(0xFFF59E0B); // Amber
      case 'Confirmed':
        return const Color(0xFF10B981); // Green
      case 'In-Progress':
        return const Color(0xFF3B82F6); // Blue
      case 'Completed':
        return const Color(0xFF6B7280); // Grey
      case 'Cancelled':
        return const Color(0xFFEF4444); // Red
      default:
        return Colors.grey;
    }
  }

  Widget _statusBadge(String? status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status ?? '-',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Booking Detail'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
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
          ? Center(
        child: Text(
          _error ?? 'Booking not found',
          style: const TextStyle(color: Colors.grey),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ===== Info Card =====
            Card(
              elevation: 1,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Booking Info',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _primaryColor,
                          ),
                        ),
                        _statusBadge(_b!['booking_status']),
                      ],
                    ),
                    const Divider(height: 20),
                    _row(
                      'Customer',
                      _b!['customer_profiles']?['users']
                      ?['full_name'] ??
                          '-',
                    ),
                    _row(
                      'Contact',
                      _b!['customer_profiles']?['users']?['phone'] ??
                          '-',
                    ),
                    _row('Service',
                        _b!['services']?['service_name'] ?? '-'),
                    _row(
                      'Date',
                      '${_b!['booking_date']} ${_b!['scheduled_time']}',
                    ),
                    _row('Address', _b!['customer_address'] ?? '-'),
                    _row(
                      'Payment',
                      'RM${_b!['total_amount']} · ${_b!['payment_status'] ?? 'Not paid'}',
                    ),
                  ],
                ),
              ),
            ),

            // ===== Payment Pending Notice =====
            if (_b!['booking_status'] == 'Confirmed' &&
                _b!['payment_status'] != 'Success')
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: _primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Slot accepted. Waiting for the customer to complete FPX payment.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ===== Special Instructions =====
            if (_b!['special_instructions'] != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.sticky_note_2_outlined,
                      color: _primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Special Instructions',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _b!['special_instructions'],
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // ===== Action Buttons =====
            if (_acting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_b!['can_accept'] == true)
                    ElevatedButton.icon(
                      onPressed: () => _update('Confirmed'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  if (_b!['can_accept'] == true)
                    OutlinedButton.icon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Decline'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: const BorderSide(
                          color: _primaryColor,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  if (_b!['can_start'] == true)
                    ElevatedButton.icon(
                      onPressed: () => _update('In-Progress'),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start Service'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  if (_b!['booking_status'] == 'In-Progress')
                    ElevatedButton.icon(
                      onPressed: () => _update('Completed'),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Complete Service'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
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
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );
}