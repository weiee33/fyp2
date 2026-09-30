import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:fyp2/Provider/services/earnings_service.dart';
import 'package:fyp2/Provider/screens/earnings/daily_earnings_screen.dart';
import 'package:fyp2/Provider/screens/earnings/weekly_earnings_screen.dart';
import 'package:fyp2/Provider/screens/earnings/month_earnings_screen.dart';
import 'package:fyp2/Provider/screens/earnings/performance_screen.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final _service = EarningsService();
  List<Map<String, dynamic>> _rows = [];
  Map<String, double> _sum = {};
  bool _loading = true;

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _service.getAllEarnings();
      final sum = _service.summarize(rows);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _sum = sum;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load earnings: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // 计算最近 7 天的每日收入
  List<double> _getLast7Days() {
    final now = DateTime.now();
    final result = List<double>.filled(7, 0);

    for (final row in _rows) {
      final dateStr = row['earned_at']?.toString() ??
          row['date']?.toString() ??
          row['created_at']?.toString();
      if (dateStr == null) continue;

      final parsed = DateTime.tryParse(dateStr);
      if (parsed == null) continue;

      final diff = now.difference(DateTime(parsed.year, parsed.month, parsed.day)).inDays;
      if (diff >= 0 && diff < 7) {
        final amount = (row['amount'] ?? row['total_amount'] ?? 0).toDouble();
        result[6 - diff] += amount;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final today = _sum['today'] ?? 0;
    final week = _sum['week'] ?? 0;
    final month = _sum['month'] ?? 0;
    final pending = _sum['pending'] ?? 0;
    final last7Days = _getLast7Days();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryColor,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Stat Cards ----
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _statCard(
                    label: 'Today',
                    value: 'RM${today.toStringAsFixed(0)}',
                    icon: Icons.today,
                    color: const Color(0xFF3B82F6),
                  ),
                  _statCard(
                    label: 'This Week',
                    value: 'RM${week.toStringAsFixed(0)}',
                    icon: Icons.date_range,
                    color: const Color(0xFF10B981),
                  ),
                  _statCard(
                    label: 'This Month',
                    value: 'RM${month.toStringAsFixed(0)}',
                    icon: Icons.calendar_month,
                    color: const Color(0xFF8B5CF6),
                  ),
                  _statCard(
                    label: 'Pending',
                    value: 'RM${pending.toStringAsFixed(0)}',
                    icon: Icons.hourglass_bottom,
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---- Chart Card ----
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.show_chart,
                              color: _primaryColor, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Earnings Trend',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Last 7 days',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: last7Days.every((v) => v == 0)
                            ? const Center(
                          child: Text(
                            'No earnings data yet',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        )
                            : BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: (last7Days.reduce((a, b) => a > b ? a : b) * 1.2)
                                .clamp(1, double.infinity),
                            barGroups: List.generate(7, (i) {
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: last7Days[i],
                                    color: const Color(0xFF60A5FA),
                                    width: 18,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ],
                              );
                            }),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 24,
                                  getTitlesWidget: (value, meta) {
                                    final now = DateTime.now();
                                    final day = now.subtract(Duration(
                                        days: 6 - value.toInt()));
                                    const labels = [
                                      'M', 'T', 'W', 'T', 'F', 'S', 'S'
                                    ];
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          top: 6),
                                      child: Text(
                                        labels[day.weekday % 7],
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles:
                                SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles:
                                SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles:
                                SideTitles(showTitles: false),
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval:
                              (last7Days.reduce((a, b) => a > b ? a : b) / 3)
                                  .clamp(1, double.infinity),
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: Colors.grey.shade200,
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Menu ----
              const Text(
                'Details',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 12),

              _menuTile(
                title: 'Daily Earnings',
                subtitle: 'View earnings by day',
                icon: Icons.calendar_today_outlined,
                color: const Color(0xFF3B82F6),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DailyEarningsScreen()),
                ),
              ),
              _menuTile(
                title: 'Weekly Earnings',
                subtitle: 'View earnings by week',
                icon: Icons.date_range_outlined,
                color: const Color(0xFF10B981),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const WeeklyEarningsScreen()),
                ),
              ),
              _menuTile(
                title: 'Monthly Earnings',
                subtitle: 'View earnings by month',
                icon: Icons.calendar_month_outlined,
                color: const Color(0xFF8B5CF6),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MonthlyEarningsScreen()),
                ),
              ),
              _menuTile(
                title: 'Performance',
                subtitle: 'View your performance metrics',
                icon: Icons.insights_outlined,
                color: const Color(0xFFF59E0B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PerformanceScreen()),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ========== Stat Card ==========
  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== Menu Tile ==========
  Widget _menuTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}