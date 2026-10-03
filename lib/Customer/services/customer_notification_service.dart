import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/account_access.dart';

class CustomerNotificationService {
  final SupabaseClient _client;
  CustomerNotificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<String> _applicationUserId() async {
    final identity = await AccountAccess.requireRole(_client, 'customer');
    return identity['user_id'] as String;
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    final uid = await _applicationUserId();
    final rows = await _client
        .from('notifications')
        .select(
          'notification_id, booking_id, notification_type, title, message, is_read, created_at',
        )
        .eq('user_id', uid)
        .isFilter('dismissed_at', null)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> markAsRead(String notificationId) async {
    final uid = await _applicationUserId();
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('notification_id', notificationId)
        .eq('user_id', uid)
        .select('notification_id')
        .single();
  }

  Future<void> markAllAsRead() async {
    final uid = await _applicationUserId();
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .isFilter('dismissed_at', null)
        .eq('is_read', false);
  }

  Future<void> deleteNotification(String notificationId) async {
    await _client.rpc(
      'customer_notification_dismiss',
      params: {'p_notification_id': notificationId},
    );
  }
}
