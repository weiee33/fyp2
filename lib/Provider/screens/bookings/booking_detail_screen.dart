import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _b;
  bool _loading = true;
  bool _acting = false;
  String? _error;

  // 临时存储查到的客户名字和电话
  String _customerName = '-';
  String _customerPhone = '-';

  // 🎨 Unified Theme Colors
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final booking = await _service.getBookingDetail(widget.bookingId);
      if (mounted) {
        setState(() {
          _b = booking;
          _error = null;
        });
        // 加载完订单后，去获取客户信息
        await _fetchCustomerInfo();
      }
    } catch (error) {
      if (mounted) setState(() => _error = bookingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 单独写一个查询客户信息的方法
  Future<void> _fetchCustomerInfo() async {
    if (_b == null) return;

    // 1. 先尝试从嵌套数据里直接拿
    final nestedUser = _b!['customer_profiles']?['users'];
    if (nestedUser != null) {
      if (mounted) {
        setState(() {
          _customerName = nestedUser['full_name']?.toString() ?? '-';
          _customerPhone = nestedUser['phone']?.toString() ?? '-';
        });
      }
      return;
    }

    // 2. 如果嵌套里没有，直接用 customer_id 去 users 表查
    final cid = _b!['customer_id']?.toString();
    if (cid != null && cid.isNotEmpty) {
      try {
        final userRow = await _client
            .from('users')
            .select('full_name, phone')
            .eq('user_id', cid)
            .maybeSingle();

        if (userRow != null && mounted) {
          setState(() {
            _customerName = userRow['full_name']?.toString() ?? '-';
            _customerPhone = userRow['phone']?.toString() ?? '-';
          });
        }
      } catch (e) {
        debugPrint('Fetch customer error: $e');
      }
    }
  }

  Future<void> _update(String status) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await _service.updateStatus(widget.bookingId, status);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(bookingError(error))),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          tr('Decline booking request'),
          style: const TextStyle(fontWeight: FontWeight.bold),
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
              if (text.isEmpty) return tr('Reason is required');
              if (text.length < 3) {
                return tr('Reason must be at least 3 characters');
              }
              if (text.length > 500) {
                return tr('Reason must not exceed 500 characters');
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: trOrNull('Please provide a reason...'),
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _borderOrange),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primaryOrange, width: 2),
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
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
            child: Text(tr('Close')),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(tr('Confirm')),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(bookingError(error))),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _acting = false);
      }
    }
  }

  // ========== Status Badge ==========
  Color _statusColor(String? status) {
    switch (status) {
      case 'Pending':
        return const Color(0xFFF59E0B);
      case 'Confirmed':
        return const Color(0xFF10B981);
      case 'In-Progress':
        return const Color(0xFF3B82F6);
      case 'Completed':
        return const Color(0xFF6B7280);
      case 'Cancelled':
        return const Color(0xFFEF4444);
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
        tr(status ?? '-'),
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
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(tr('Booking Detail')),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryOrange))
          : _b == null
          ? Center(
        child: Text(
          tr(_error ?? 'Booking not found'),
          style: const TextStyle(color: Colors.grey),
        ),
      )
          : RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
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
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(_error!),
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
                side: const BorderSide(color: _borderOrange),
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
                        Text(
                          tr('Booking Info'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _primaryOrange,
                          ),
                        ),
                        _statusBadge(_b!['booking_status']),
                      ],
                    ),
                    const Divider(height: 20),
                    // 👇 这里使用了我们查到的 _customerName 和 _customerPhone
                    _row('Customer', _customerName),
                    _row('Contact', _customerPhone),
                    _row(
                      'Service',
                      _b!['services']?['service_name'] ?? '-',
                    ),
                    _row(
                      'Date',
                      '${_b!['booking_date']} ${_b!['scheduled_time']}',
                    ),
                    _row('Address', _b!['customer_address'] ?? '-'),
                    _row(
                      'Payment',
                      tr("RM{0} · {1}", [
                        _b!['total_amount'],
                        tr(
                          _b!['payment_status']?.toString() ??
                              'Not paid',
                        ),
                      ]),
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
                  color: _lightOrange,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _borderOrange,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: _primaryOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(
                          'Slot accepted. Waiting for the customer to complete FPX payment.',
                        ),
                        style: const TextStyle(
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
                  border: Border.all(color: _borderOrange),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.sticky_note_2_outlined,
                      color: _primaryOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Special Instructions'),
                            style: const TextStyle(
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

            const SizedBox(height: 24),

            // ===== Action Buttons =====
            if (_acting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    color: _primaryOrange,
                  ),
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
                      label: Text(tr('Accept')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
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
                      label: Text(tr('Decline')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryOrange,
                        side: const BorderSide(
                          color: _primaryOrange,
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
                      label: Text(tr('Start Service')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
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
                      label: Text(tr('Complete Service')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
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

            const SizedBox(height: 40),
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
            tr(label),
            style: const TextStyle(color: Colors.grey, fontSize: 13),
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