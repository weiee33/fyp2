import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerNotificationService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// Fetch all notifications for the current customer[cite: 502, 503]
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final uid = currentUser?.id;
    if (uid == null) return [];

    final res = await _client
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// Mark a specific notification as read[cite: 455]
  Future<void> markAsRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('notification_id', notificationId);
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    final uid = currentUser?.id;
    if (uid == null) return;

    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }

  /// Delete a notification (triggered by swipe-to-dismiss)
  Future<void> deleteNotification(String notificationId) async {
    await _client
        .from('notifications')
        .delete()
        .eq('notification_id', notificationId);
  }
}