import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getMyNotifications() async {
    final uid = _client.auth.currentUser!.id;
    final res = await _client
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> markAsRead(String id) async {
    await _client
        .from('notifications')
        .update({'is_read': true}).eq('notification_id', id);
  }

  Future<int> getUnreadCount() async {
    final uid = _client.auth.currentUser!.id;
    final res = await _client
        .from('notifications')
        .select('notification_id')
        .eq('user_id', uid)
        .eq('is_read', false);
    return (res as List).length;
  }
}