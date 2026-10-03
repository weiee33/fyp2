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

  int _chartView = 0;

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

  DateTime? _parseDate(Map<String, dynamic> row) {
    final dateStr = row['earned_at']?.toString() ??
        row['bookings']?['booking_date']?.toString() ??
        row['booking_date']?.toString() ??
        row['date']?.toString() ??
        row['created_at']?.toString();
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  double _amount(Map<String, dynamic> row) {
    return (row['net_earnings'] ?? row['amount'] ?? row['total_amount'] ?? 0)
        .toDouble();
  }

  List<double> _getLast7Days() {
    final now = DateTime.now();
    final result = List<double>.filled(7, 0);
    for (final row in _rows) {
      final parsed = _parseDate(row);
      if (parsed == null) continue;
      final diff = now
          .difference(DateTime(parsed.year, parsed.month, parsed.day))
          .inDays;
      if (diff >= 0 && diff < 7) {
        result[6 - diff] += _amount(row);
      }
    }
    return result;
  }

  List<String> _getLast7DayLabels() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return labels[day.weekday % 7];
    });
  }

  List<double> _getCurrentMonthDays() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final result = List<double>.filled(daysInMonth, 0);

    for (final row in _rows) {
      final parsed = _parseDate(row);
      if (parsed == null) continue;
      if (parsed.year == now.year && parsed.month == now.month) {
        final dayIndex = parsed.day - 1;
        if (dayIndex >= 0 && dayIndex < daysInMonth) {
          result[dayIndex] += _amount(row);
        }
      }
    }
    return result;
  }

  List<String> _getCurrentMonthLabels() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return List.generate(daysInMonth, (i) => '${i + 1}');
  }

  List<double> _getCurrentYearMonths() {
    final now = DateTime.now();
    final result = List<double>.filled(12, 0);

    for (final row in _rows) {
      final parsed = _parseDate(row);
      if (parsed == null) continue;
      if (parsed.year == now.year) {
        final monthIndex = parsed.month - 1;
        if (monthIndex >= 0 && monthIndex < 12) {
          result[monthIndex] += _amount(row);
        }
      }
    }
    return result;
  }

  List<String> _getCurrentYearLabels() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months;
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

    List<double> chartValues;
    List<String> chartLabels;
    String chartSubtitle;
    switch (_chartView) {
      case 1:
        chartValues = _getCurrentMonthDays();
        chartLabels = _getCurrentMonthLabels();
        chartSubtitle = 'This Month';
        break;
      case 2:
        chartValues = _getCurrentYearMonths();
        chartLabels = _getCurrentYearLabels();
        chartSubtitle = 'This Year';
        break;
      default:
        chartValues = _getLast7Days();
        chartLabels = _getLast7DayLabels();
        chartSubtitle = 'Last 7 days';
    }

    final hasData = chartValues.any((v) => v > 0);
    final maxY = hasData
        ? chartValues.reduce((a, b) => a > b ? a : b) * 1.2
        : 10.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryOrange,
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
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _borderOrange),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.show_chart,
                              color: _primaryOrange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Earnings Trend',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _primaryOrange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chartSubtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),

                      _buildToggle(),
                      const SizedBox(height: 16),

                      SizedBox(
                        height: 220,
                        child: hasData
                            ? BarChart(
                          BarChartData(
                            alignment:
                            BarChartAlignment.spaceAround,
                            maxY: maxY,
                            barGroups:
                            List.generate(chartValues.length, (i) {
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: chartValues[i],
                                    color: _primaryOrange,
                                    width: chartValues.length > 20
                                        ? 6
                                        : (chartValues.length > 8
                                        ? 12
                                        : 18),
                                    borderRadius:
                                    BorderRadius.circular(6),
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
                                  interval: chartValues.length > 20
                                      ? 3
                                      : 1,
                                  getTitlesWidget: (value, meta) {
                                    final idx = value.toInt();
                                    if (idx < 0 ||
                                        idx >= chartLabels.length) {
                                      return const SizedBox();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          top: 6),
                                      child: Text(
                                        chartLabels[idx],
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false),
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval:
                              (maxY / 3).clamp(1, double.infinity),
                              getDrawingHorizontalLine: (value) =>
                                  FlLine(
                                    color: Colors.grey.shade200,
                                    strokeWidth: 1,
                                  ),
                            ),
                            borderData:
                            FlBorderData(show: false),
                          ),
                        )
                            : const Center(
                          child: Text(
                            'No earnings data yet',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
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
                  color: _primaryOrange,
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

  Widget _buildToggle() {
    return Container(
      decoration: BoxDecoration(
        color: _lightOrange,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderOrange),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _toggleBtn('7 Days', 0),
          _toggleBtn('Monthly', 1),
          _toggleBtn('Yearly', 2),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, int value) {
    final selected = _chartView == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _chartView = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _primaryOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _primaryOrange,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderOrange),
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
                    color: color.withValues(alpha: 0.15),
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
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
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