import 'package:flutter/material.dart';
import '../../services/booking_service.dart';

class AiScheduleScreen extends StatefulWidget {
  const AiScheduleScreen({super.key});

  @override
  State<AiScheduleScreen> createState() => _AiScheduleScreenState();
}

class _AiScheduleScreenState extends State<AiScheduleScreen> {
  final _service = BookingService();

  List<Map<String, dynamic>> _schedule = [];
  double _totalDistanceKm = 0;
  int _totalTravelMin = 0;
  double _estimatedEarnings = 0;
  bool _loading = true;

  static const _primaryColor = Color(0xFFF97316); // Orange
  static const _accentColor = Color(0xFFFFF7ED); // Light orange tint

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Get today's confirmed bookings
      final bookings = await _service.getMyBookings(status: 'Confirmed');
      if (!mounted) return;

      final optimized = _optimizeSchedule(bookings);

      setState(() {
        _schedule = optimized['schedule'] as List<Map<String, dynamic>>;
        _totalDistanceKm = optimized['totalDistance'] as double;
        _totalTravelMin = optimized['totalTravel'] as int;
        _estimatedEarnings = optimized['earnings'] as double;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to build schedule: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Nearest-neighbor heuristic (Module 11)
  /// Simulated distances: uses booking order as pseudo-locations.
  /// In production, replace with real lat/lng + Google Distance Matrix.
  Map<String, dynamic> _optimizeSchedule(
      List<Map<String, dynamic>> bookings) {
    if (bookings.isEmpty) {
      return {
        'schedule': <Map<String, dynamic>>[],
        'totalDistance': 0.0,
        'totalTravel': 0,
        'earnings': 0.0,
      };
    }

    // Simulate travel distance between jobs: 6~15 km random-ish based on index
    // Replace with real geo distance later
    final jobs = List<Map<String, dynamic>>.from(bookings);

    // Nearest neighbor: start from first, always pick nearest remaining
    final ordered = <Map<String, dynamic>>[];
    final visited = <int>{};
    int current = 0;
    ordered.add(jobs[current]);
    visited.add(current);

    double totalDist = 0;
    int totalTravel = 0;

    while (visited.length < jobs.length) {
      int bestNext = -1;
      double bestDist = double.infinity;

      for (int i = 0; i < jobs.length; i++) {
        if (visited.contains(i)) continue;
        final d = _simulatedDistance(current, i);
        if (d < bestDist) {
          bestDist = d;
          bestNext = i;
        }
      }

      if (bestNext == -1) break;
      visited.add(bestNext);
      totalDist += bestDist;
      totalTravel += (bestDist * 3).round(); // assume 3 min per km in city
      ordered.add(jobs[bestNext]);
      current = bestNext;
    }

    // Add earnings
    double earnings = 0;
    for (final j in ordered) {
      earnings +=
          (j['total_amount'] as num?)?.toDouble() ?? 0;
    }

    return {
      'schedule': ordered,
      'totalDistance': totalDist,
      'totalTravel': totalTravel,
      'earnings': earnings,
    };
  }

  double _simulatedDistance(int a, int b) {
    // Deterministic pseudo-distance between 5 and 15 km
    final diff = (a - b).abs();
    return (5 + (diff * 2.5)) % 15 + 5;
  }

  String _formatTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('AI Smart Schedule'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryColor,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Date header
              Text(
                _formatDate(DateTime.now()),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 12),

              // Stats grid
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _statCard(
                    label: 'Total Jobs',
                    value: '${_schedule.length}',
                    icon: Icons.work_outline,
                    color: _primaryColor,
                  ),
                  _statCard(
                    label: 'Total Distance',
                    value: '${_totalDistanceKm.toStringAsFixed(0)} km',
                    icon: Icons.route_outlined,
                    color: const Color(0xFF10B981),
                  ),
                  _statCard(
                    label: 'Travel Time',
                    value: _formatTime(_totalTravelMin),
                    icon: Icons.timer_outlined,
                    color: const Color(0xFF8B5CF6),
                  ),
                  _statCard(
                    label: 'Est. Earnings',
                    value:
                    'RM${_estimatedEarnings.toStringAsFixed(0)}',
                    icon: Icons.attach_money,
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const Text(
                'Optimized Route',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 12),

              if (_schedule.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No confirmed bookings today',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ...List.generate(
                  _schedule.length,
                      (i) => _scheduleTile(_schedule[i], i + 1),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scheduleTile(Map<String, dynamic> b, int step) {
    final cust = b['customer_profiles']?['users']?['full_name'] ??
        'Customer';
    final svc = b['services']?['service_name'] ?? 'Service';
    final address = b['customer_address']?.toString() ?? 'Address';
    final duration =
        (b['estimated_duration'] as num?)?.toInt() ?? 60;
    final amount = (b['total_amount'] as num?)?.toDouble() ?? 0;

    return Card(
      elevation: 1,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step number circle
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _accentColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$step',
                style: const TextStyle(
                  color: _primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    svc,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cust,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '$duration min',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.attach_money,
                          size: 13, color: Colors.grey),
                      Text(
                        'RM${amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}