import 'package:flutter/material.dart';
import '../../services/earnings_service.dart';

class DailyEarningsScreen extends StatefulWidget {
  const DailyEarningsScreen({super.key});

  @override
  State<DailyEarningsScreen> createState() => _DailyEarningsScreenState();
}

class _DailyEarningsScreenState extends State<DailyEarningsScreen> {
  final _service = EarningsService();
  List<Map<String, dynamic>> _today = [];
  double _total = 0;
  bool _loading = true;

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final all = await _service.getAllEarnings();
      final now = DateTime.now();
      final list = all.where((r) {
        final raw = r['bookings']?['booking_date'] ?? r['created_at'];
        final d = DateTime.tryParse(raw?.toString() ?? '');
        return d != null &&
            d.year == now.year &&
            d.month == now.month &&
            d.day == now.day;
      }).toList();

      final total = list.fold<double>(
        0,
            (s, r) => s + ((r['net_earnings'] as num?)?.toDouble() ?? 0),
      );

      if (!mounted) return;
      setState(() {
        _today = list;
        _total = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  String _shortBookingId(Map<String, dynamic> r) {
    final raw = r['bookings']?['booking_id']?.toString();
    if (raw == null || raw.isEmpty) return '-';
    return raw.length >= 6 ? raw.substring(0, 6) : raw;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dateText =
        '${today.day.toString().padLeft(2, '0')} / ${today.month.toString().padLeft(2, '0')} / ${today.year}';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Today's Earnings"),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryOrange,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Total Card ----
              Card(
                elevation: 2,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _borderOrange),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _lightOrange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.today,
                              color: _primaryOrange,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Total Earned Today',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'RM${_total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: _primaryOrange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _lightOrange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 14,
                              color: _primaryOrange,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_today.length} transaction${_today.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _primaryOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Section Title ----
              if (_today.isNotEmpty) ...[
                const Text(
                  'Transactions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _primaryOrange,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ---- Transactions List ----
              if (_today.isEmpty)
                _buildEmptyState()
              else
                ..._today.map((r) => _transactionTile(r)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderOrange),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: Colors.grey,
            ),
            SizedBox(height: 12),
            Text(
              'No earnings today',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Completed jobs will appear here',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionTile(Map<String, dynamic> r) {
    final bookingId = _shortBookingId(r);
    final serviceName =
        r['bookings']?['services']?['service_name']?.toString() ?? 'Service';
    final amount = (r['net_earnings'] as num?)?.toDouble() ?? 0;
    final status = r['payout_status']?.toString() ?? 'Pending';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _lightOrange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.attach_money,
                color: _primaryOrange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    serviceName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '#$bookingId',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusBadge(status),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              'RM${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _primaryOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;

    switch (status.toLowerCase()) {
      case 'completed':
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF065F46);
        break;
      case 'processing':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1E40AF);
        break;
      default:
      // Pending
        bg = _lightOrange;
        fg = _primaryOrange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}