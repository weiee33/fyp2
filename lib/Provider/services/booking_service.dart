import 'package:supabase_flutter/supabase_flutter.dart';

class BookingService {
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

  Future<List<Map<String, dynamic>>> getMyBookings({String? status}) async {
    final pid = await _providerId();
    if (pid == null) return [];
    var q = _client
        .from('bookings')
        .select('''
          *,
          customer_profiles!inner(users!inner(full_name, phone)),
          services!bookings_service_id_fkey!inner(service_name)
        ''')
        .eq('provider_id', pid);
    if (status != null) q = q.eq('booking_status', status);
    final res = await q.order('scheduled_datetime', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<Map<String, dynamic>?> getBookingDetail(String bookingId) async {
    final res = await _client
        .from('bookings')
        .select('''
          *,
          customer_profiles!inner(users!inner(full_name, phone)),
          services!bookings_service_id_fkey!inner(service_name)
        ''')
        .eq('booking_id', bookingId)
        .maybeSingle();
    return res;
  }

  Future<void> updateStatus(String bookingId, String status) async {
    final patch = <String, dynamic>{'booking_status': status};
    if (status == 'Confirmed') {
      patch['accepted_at'] = DateTime.now().toIso8601String();
    } else if (status == 'In-Progress') {
      patch['started_at'] = DateTime.now().toIso8601String();
    } else if (status == 'Completed') {
      patch['completed_at'] = DateTime.now().toIso8601String();
    }
    await _client.from('bookings').update(patch).eq('booking_id', bookingId);
  }

  Future<void> cancel(String bookingId, String reason) async {
    await _client.from('bookings').update({
      'booking_status': 'Cancelled',
      'cancellation_reason': reason,
      'cancelled_at': DateTime.now().toIso8601String(),
    }).eq('booking_id', bookingId);
  }

  Future<List<Map<String, dynamic>>> getChatMessages(String bookingId) async {
    final res = await _client
        .from('notifications')
        .select()
        .eq('booking_id', bookingId)
        .eq('notification_type', 'Message')
        .order('created_at');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> sendMessage(String bookingId, String message) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('notifications').insert({
      'user_id': uid,
      'booking_id': bookingId,
      'notification_type': 'Message',
      'title': 'Provider message',
      'message': message,
    });
  }
}