import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _profile = await _service.getPerformance();
    _reviews = await _service.getReviews();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final rating = _profile?['overall_rating'] ?? 0;
    final reviews = _profile?['total_reviews'] ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Overall Rating: $rating',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('$reviews reviews',
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Customer Reviews',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._reviews.map((r) {
            final name = r['customer_profiles']?['users']?['full_name'] ?? 'Customer';
            return Card(
              child: ListTile(
                title: Text('$name · ${r['rating_score']} ★'),
                subtitle: Text(r['review_comment'] ?? ''),
              ),
            );
          }),
        ],
      ),
    );
  }
}