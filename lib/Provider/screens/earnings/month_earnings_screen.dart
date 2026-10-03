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

  // Weekly trend for the current month (Week 1 ~ Week 5)
  final List<double> _weeklyTotals = List.filled(5, 0);

  bool _loading = true;

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  // Pie chart palette (kept colorful to distinguish categories)
  static const _palette = [
    Color(0xFFFF6B00),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

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

      _byCategory.clear();
      for (var i = 0; i < _weeklyTotals.length; i++) {
        _weeklyTotals[i] = 0;
      }
      double total = 0;

      for (final r in all) {
        final raw = r['bookings']?['booking_date'] ?? r['created_at'];
        final d = DateTime.tryParse(raw?.toString() ?? '');
        if (d == null) continue;
        if (d.year != now.year || d.month != now.month) continue;

        final amt = (r['net_earnings'] as num?)?.toDouble() ?? 0;
        total += amt;

        final cat = r['bookings']?['services']?['service_name']?.toString() ??
            'Other';
        _byCategory[cat] = (_byCategory[cat] ?? 0) + amt;

        final weekIdx = ((d.day - 1) ~/ 7).clamp(0, 4);
        _weeklyTotals[weekIdx] += amt;
      }

      if (!mounted) return;
      setState(() {
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthName = _monthName(now.month);

    final hasCategory = _byCategory.isNotEmpty;
    final hasTrend = _weeklyTotals.any((v) => v > 0);

    final sortedCategories = _byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('This Month'),
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
                              Icons.calendar_month,
                              color: _primaryOrange,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Total This Month',
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
                        '$monthName ${now.year}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Pie Chart Card ----
              if (hasCategory) ...[
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
                            Icon(Icons.pie_chart_outline,
                                color: _primaryOrange, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Service Popularity',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _primaryOrange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Earnings by service category',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: List.generate(
                                sortedCategories.length,
                                    (i) {
                                  final e = sortedCategories[i];
                                  final pct = _total > 0
                                      ? (e.value / _total * 100)
                                      : 0;
                                  return PieChartSectionData(
                                    value: e.value,
                                    title: '${pct.toStringAsFixed(0)}%',
                                    color: _palette[i % _palette.length],
                                    radius: 60,
                                    titleStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Legend
                        ...List.generate(
                          sortedCategories.length,
                              (i) {
                            final e = sortedCategories[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color:
                                      _palette[i % _palette.length],
                                      borderRadius:
                                      BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      e.key,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'RM${e.value.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _primaryOrange,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ---- Weekly Trend Card ----
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
                            'Weekly Trend',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _primaryOrange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Earnings per week this month',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 180,
                        child: hasTrend
                            ? LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: (_weeklyTotals
                                  .reduce((a, b) =>
                              a > b ? a : b) /
                                  3)
                                  .clamp(1, 99999),
                              getDrawingHorizontalLine: (value) =>
                                  FlLine(
                                    color: Colors.grey.shade200,
                                    strokeWidth: 1,
                                  ),
                            ),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 26,
                                  getTitlesWidget: (v, meta) {
                                    final i = v.toInt();
                                    if (i < 0 || i > 4) {
                                      return const SizedBox();
                                    }
                                    return Padding(
                                      padding:
                                      const EdgeInsets.only(
                                          top: 6),
                                      child: Text(
                                        'Wk ${i + 1}',
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
                            borderData:
                            FlBorderData(show: false),
                            minX: 0,
                            maxX: 4,
                            minY: 0,
                            lineBarsData: [
                              LineChartBarData(
                                spots: List.generate(
                                  5,
                                      (i) => FlSpot(
                                      i.toDouble(),
                                      _weeklyTotals[i]),
                                ),
                                isCurved: true,
                                color: _primaryOrange,
                                barWidth: 3,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, pct,
                                      bar, idx) =>
                                      FlDotCirclePainter(
                                        radius: 4,
                                        color: Colors.white,
                                        strokeWidth: 2,
                                        strokeColor: _primaryOrange,
                                      ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: _primaryOrange
                                      .withValues(alpha: 0.15),
                                ),
                              ),
                            ],
                          ),
                        )
                            : const Center(
                          child: Text(
                            'No earnings this month',
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
            ],
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }
}