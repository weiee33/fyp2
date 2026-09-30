import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/earnings_service.dart';

class WeeklyEarningsScreen extends StatefulWidget {
  const WeeklyEarningsScreen({super.key});
  @override
  State<WeeklyEarningsScreen> createState() => _WeeklyEarningsScreenState();
}

class _WeeklyEarningsScreenState extends State<WeeklyEarningsScreen> {
  final _service = EarningsService();
  double _total = 0;
  final List<double> _days = List.filled(7, 0);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _service.getAllEarnings();
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    for (final r in all) {
      final d = DateTime.tryParse(
          (r['bookings']?['booking_date'] ?? r['created_at']) as String);
      if (d == null || d.isBefore(start)) continue;
      final i = d.weekday - 1;
      _days[i] += (r['net_earnings'] as num?)?.toDouble() ?? 0;
      _total += (r['net_earnings'] as num?)?.toDouble() ?? 0;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('This Week')),
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
                  SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        barGroups: List.generate(
                            7,
                            (i) => BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                      toY: _days[i],
                                      color: const Color(0xFF60A5FA)),
                                ])),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) => Text(
                                  ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                                      [v.toInt()]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}