import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/earnings_service.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final _service = EarningsService();
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _profile = await _service.getPerformance();
      _reviews = await _service.getReviews();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load performance: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 从 _reviews 里统计每个星级出现的次数
  List<int> _ratingDistribution() {
    final counts = List<int>.filled(5, 0); // index 0 = 1★, index 4 = 5★
    for (final r in _reviews) {
      final score = (r['rating_score'] as num?)?.toInt() ?? 0;
      if (score >= 1 && score <= 5) {
        counts[score - 1]++;
      }
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final rating = (_profile?['overall_rating'] ?? 0).toDouble();
    final totalReviews = _profile?['total_reviews'] ?? _reviews.length;
    final completionRate = _profile?['completion_rate'] ?? 98;
    final onTimeRate = _profile?['on_time_rate'] ?? 95;
    final responseTime = _profile?['response_time_min'] ?? 5;

    final dist = _ratingDistribution();
    final maxCount = dist.isEmpty
        ? 1
        : dist.reduce((a, b) => a > b ? a : b).clamp(1, 9999);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Performance'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ============ Overall Rating Card ============
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'Overall Rating',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            '/ 5.0',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final filled = i < rating.round();
                        return Icon(
                          filled ? Icons.star : Icons.star_border,
                          color: Colors.orange,
                          size: 22,
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$totalReviews reviews',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ============ Rating Distribution Bar Chart ============
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
                        Icon(Icons.bar_chart, color: _primaryColor, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Rating Distribution',
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
                      'How customers rated your service',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxCount * 1.2,
                          barGroups: List.generate(5, (i) {
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: dist[i].toDouble(),
                                  color: _primaryColor,
                                  width: 22,
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
                                reservedSize: 28,
                                getTitlesWidget: (value, meta) {
                                  final stars = (value.toInt() + 1);
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '$stars★',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: (maxCount / 3).clamp(1, 9999),
                                getTitlesWidget: (value, meta) {
                                  if (value == 0) return const SizedBox();
                                  return Text(
                                    value.toInt().toString(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: (maxCount / 3).clamp(1, 9999),
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
            const SizedBox(height: 16),

            // ============ Key Metrics ============
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    label: 'Completion Rate',
                    value: '$completionRate%',
                    icon: Icons.task_alt,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricCard(
                    label: 'On-Time Rate',
                    value: '$onTimeRate%',
                    icon: Icons.schedule,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _metricCard(
              label: 'Avg. Response Time',
              value: '$responseTime min',
              icon: Icons.timer_outlined,
              color: Colors.orange,
              fullWidth: true,
            ),
            const SizedBox(height: 20),

            // ============ View Reviews Button ============
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  _showReviewsSheet(context);
                },
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text(
                  'View Reviews',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ============ Metric Card ============
  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool fullWidth = false,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
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
          ],
        ),
      ),
    );
  }

  // ============ Reviews Sheet ============
  void _showReviewsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Customer Reviews',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: _reviews.isEmpty
                  ? const Center(
                child: Text(
                  'No reviews yet',
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : ListView.builder(
                controller: controller,
                padding: const EdgeInsets.all(16),
                itemCount: _reviews.length,
                itemBuilder: (_, i) {
                  final r = _reviews[i];
                  final name =
                      r['customer_profiles']?['users']?['full_name'] ??
                          'Customer';
                  final score = r['rating_score'] ?? 0;
                  final comment = r['review_comment'] ?? '';
                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDBEAFE),
                        child: Text(
                          name.toString().isNotEmpty
                              ? name.toString()[0].toUpperCase()
                              : 'C',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            name.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$score ★',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      subtitle: comment.toString().isEmpty
                          ? null
                          : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(comment.toString()),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}