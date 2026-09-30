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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _service.getAllEarnings();
    final now = DateTime.now();
    _today = all.where((r) {
      final d = DateTime.tryParse(
          (r['bookings']?['booking_date'] ?? r['created_at']) as String);
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day;
    }).toList();
    _total = _today.fold(
        0, (s, r) => s + ((r['net_earnings'] as num?)?.toDouble() ?? 0));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Earnings")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total: RM${_total.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ..._today.map((r) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                  '#${r['bookings']?['booking_id']?.toString().substring(0, 6) ?? '-'}  RM${r['net_earnings']}'),
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}