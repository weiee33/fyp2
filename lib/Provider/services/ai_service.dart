import 'package:supabase_flutter/supabase_flutter.dart';

class AiService {
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

  Future<List<Map<String, dynamic>>> getJobRecommendations() async {
    final pid = await _providerId();
    if (pid == null) return [];
    final res = await _client
        .from('ai_provider_recommendations')
        .select()
        .eq('provider_id', pid)
        .eq('status', 'Pending')
        .order('match_percentage', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> respondToRecommendation(String id, String status) async {
    await _client
        .from('ai_provider_recommendations')
        .update({'status': status}).eq('recommendation_id', id);
  }

  Future<Map<String, dynamic>?> getScheduleForDate(DateTime date) async {
    final pid = await _providerId();
    if (pid == null) return null;
    return await _client
        .from('ai_schedules')
        .select()
        .eq('provider_id', pid)
        .eq('schedule_date', date.toIso8601String().substring(0, 10))
        .maybeSingle();
  }

  Future<void> saveSchedule({
    required DateTime date,
    required List<String> bookingIds,
    required List<Map<String, dynamic>> route,
    required double totalDistanceKm,
    required int totalTravelMin,
    required double estimatedEarnings,
  }) async {
    final pid = await _providerId();
    if (pid == null) return;
    await _client.from('ai_schedules').upsert({
      'provider_id': pid,
      'schedule_date': date.toIso8601String().substring(0, 10),
      'booking_ids': bookingIds,
      'route_order': route,
      'total_distance_km': totalDistanceKm,
      'total_travel_time': totalTravelMin,
      'optimized_score': estimatedEarnings,
      'is_optimized': true,
    });
  }
}