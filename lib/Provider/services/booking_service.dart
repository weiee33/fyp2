import '../../shared/chat/chat_service.dart';
import '../../Customer/services/customer_transaction_service.dart';
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

  final Map<String,String> _conversationIds = {};
  String? _retryBody, _retryId;
  Future<String> _chatId(String bookingId) async => _conversationIds[bookingId] ??= await ChatService().open(bookingId: bookingId);
  Future<List<Map<String,dynamic>>> getChatMessages(String bookingId) async {
    final chat = ChatService();
    final id = await _chatId(bookingId);
    final result = await chat.history(id);
    final rows = ChatService.rows(result['messages']);
    if(rows.isNotEmpty) await chat.manage(id, 'read', readThrough: (rows.first['message_id'] as num).toInt());
    return rows.reversed.map((m) => {...m, 'message': m['body']}).toList();
  }
  Future<void> sendMessage(String bookingId,String message) async {
    final body = '$bookingId:$message';
    if(_retryBody != body) { _retryBody = body; _retryId = CustomerTransactionService.newRequestId(); }
    await ChatService().send(await _chatId(bookingId), message, _retryId!);
    _retryBody = null; _retryId = null;
  }
}
