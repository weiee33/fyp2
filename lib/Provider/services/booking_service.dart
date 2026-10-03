import 'package:supabase_flutter/supabase_flutter.dart';

class BookingService {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getMyBookings({String? status}) async {
    final res = await _client.rpc(
      'provider_booking_list',
      params: {'p_status': status},
    );
    return List<Map<String, dynamic>>.from(res);
  }

  Future<Map<String, dynamic>?> getBookingDetail(String bookingId) async {
    final res = await _client.rpc(
      'provider_booking_list',
      params: {'p_booking_id': bookingId},
    );
    final rows = List<Map<String, dynamic>>.from(res as List);
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> updateStatus(String bookingId, String status) async {
    if (status == 'Confirmed') {
      await _client.rpc(
        'provider_booking_reply',
        params: {'p_booking_id': bookingId, 'p_accept': true},
      );
    } else {
      await _client.rpc(
        'provider_booking_progress',
        params: {'p_booking_id': bookingId, 'p_status': status},
      );
    }
  }

  Future<void> cancel(String bookingId, String reason) async {
    await _client.rpc(
      'provider_booking_reply',
      params: {
        'p_booking_id': bookingId,
        'p_accept': false,
        'p_reason': reason,
      },
    );
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
