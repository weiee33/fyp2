import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/earnings_service.dart';

class MonthlyEarningsScreen extends StatefulWidget {
  const MonthlyEarningsScreen({super.key});
  @override
  State<MonthlyEarningsScreen> createState() => _MonthlyEarningsScreenState();
}

class _MonthlyEarningsScreenState extends State<MonthlyEarningsScreen> {
  final _service = EarningsService();
  double _total = 0;
  final Map<String, double> _byCategory = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _service.getAllEarnings();
    final now = DateTime.now();
    for (final r in all) {
      final d = DateTime.tryParse(
          (r['bookings']?['booking_date'] ?? r['created_at']) as String);
      if (d == null || d.year != now.year || d.month != now.month) continue;
      final amt = (r['net_earnings'] as num?)?.toDouble() ?? 0;
      _total += amt;
      final cat = r['bookings']?['services']?['service_name'] ?? 'Other';
      _byCategory[cat] = (_byCategory[cat] ?? 0) + amt;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('This Month')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  Text('Total: RM${_total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (_byCategory.isNotEmpty)
                    SizedBox(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sections: _byCategory.entries
                              .map((e) => PieChartSectionData(
                                    value: e.value,
                                    title: e.key,
                                    radius: 80,
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ..._byCategory.entries.map((e) => ListTile(
                        title: Text(e.key),
                        trailing: Text('RM${e.value.toStringAsFixed(0)}'),
                      )),
                ],
              ),
            ),
    );
  }
}