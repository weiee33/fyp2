import 'package:supabase_flutter/supabase_flutter.dart';

class EarningsService {
  final _client = Supabase.instance.client;

  Future<String?> _providerId() async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('provider_profiles')
        .select('provider_id')
        .eq('user_id', uid)
        .maybeSingle();
    return row?['provider_id'] as String?;
  }

  Future<List<Map<String, dynamic>>> getAllEarnings() async {
    final pid = await _providerId();
    if (pid == null) return [];
    final res = await _client
        .from('provider_earnings')
        .select('*, bookings!inner(booking_date, services!inner(service_name))')
        .eq('provider_id', pid)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Map<String, double> summarize(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();
    double today = 0, week = 0, month = 0, pending = 0;
    for (final r in rows) {
      final date = DateTime.tryParse(
              (r['bookings']?['booking_date'] ?? r['created_at']) as String) ??
          now;
      final net = (r['net_earnings'] as num?)?.toDouble() ?? 0;
      final status = r['payout_status'] as String? ?? 'Pending';

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) today += net;
      if (date.isAfter(now.subtract(Duration(days: now.weekday - 1)))) {
        week += net;
      }
      if (date.year == now.year && date.month == now.month) month += net;
      if (status != 'Completed') pending += net;
    }
    return {
      'today': today,
      'week': week,
      'month': month,
      'pending': pending,
    };
  }

  Future<Map<String, dynamic>?> getPerformance() async {
    final pid = await _providerId();
    if (pid == null) return null;
    return await _client
        .from('provider_profiles')
        .select('overall_rating, total_reviews')
        .eq('provider_id', pid)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> getReviews() async {
    final pid = await _providerId();
    if (pid == null) return [];
    final res = await _client
        .from('reviews')
        .select('*, customer_profiles!inner(users!inner(full_name))')
        .eq('provider_id', pid)
        .eq('is_flagged', false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }
}