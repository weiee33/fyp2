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

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
      final today = DateTime(now.year, now.month, now.day);
      final start = today.subtract(Duration(days: now.weekday - 1));
      final end = start.add(const Duration(days: 7));

      for (var i = 0; i < 7; i++) {
        _days[i] = 0;
      }
      double total = 0;

      for (final r in all) {
        final raw = r['bookings']?['booking_date'] ?? r['created_at'];
        final d = DateTime.tryParse(raw?.toString() ?? '');
        if (d == null) continue;
        final day = DateTime(d.year, d.month, d.day);
        if (day.isBefore(start) || !day.isBefore(end)) continue;

        final i = day.weekday - 1;
        final amount = (r['net_earnings'] as num?)?.toDouble() ?? 0;
        _days[i] += amount;
        total += amount;
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

  int _busiestDayIndex() {
    int best = 0;
    for (var i = 1; i < 7; i++) {
      if (_days[i] > _days[best]) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    final end = start.add(const Duration(days: 6));
    final rangeText =
        '${start.day} ${_monthShort(start.month)} – ${end.day} ${_monthShort(end.month)} ${end.year}';

    final maxVal = _days.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal > 0 ? maxVal * 1.2 : 10.0;
    final hasData = _days.any((v) => v > 0);
    final busiestIdx = _busiestDayIndex();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('This Week'),
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
                              Icons.date_range,
                              color: _primaryOrange,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Total This Week',
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
                        rangeText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---- Busiest Day Card ----
              if (hasData) ...[
                Card(
                  elevation: 1,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: _borderOrange),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _lightOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.local_fire_department,
                            color: _primaryOrange,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Busiest Day',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _dayLabels[busiestIdx],
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryOrange,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'RM${_days[busiestIdx].toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _primaryOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

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
                          Icon(Icons.bar_chart,
                              color: _primaryOrange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Daily Breakdown',
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
                        'Mon – Sun',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 220,
                        child: hasData
                            ? BarChart(
                          BarChartData(
                            alignment:
                            BarChartAlignment.spaceAround,
                            maxY: maxY,
                            barGroups:
                            List.generate(7, (i) {
                              final isBusiest = i == busiestIdx;
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: _days[i],
                                    // Busiest day darker orange,
                                    // others lighter orange
                                    color: isBusiest
                                        ? const Color(0xFFE85D00)
                                        : const Color(0xFFFFB380),
                                    width: 22,
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
                                  reservedSize: 28,
                                  getTitlesWidget: (v, meta) {
                                    final i = v.toInt();
                                    if (i < 0 || i > 6) {
                                      return const SizedBox();
                                    }
                                    return Padding(
                                      padding:
                                      const EdgeInsets.only(
                                          top: 6),
                                      child: Text(
                                        _dayLabels[i]
                                            .substring(0, 1),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontWeight:
                                          FontWeight.w600,
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
                              (maxY / 3).clamp(1, 9999),
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
                            'No earnings this week',
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

  String _monthShort(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }
}