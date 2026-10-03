import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../Customer/services/customer_transaction_service.dart';

class ChatService {
  final SupabaseClient? _client;
  final CustomerRpc? _rpcOverride;
  ChatService({SupabaseClient? client, CustomerRpc? rpc})
    : _client = client,
      _rpcOverride = rpc;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  bool get isLive => _rpcOverride == null;
  Future<dynamic> _rpc(String name, Map<String, dynamic> params) async =>
      _rpcOverride != null
      ? await _rpcOverride(name, params)
      : await client.rpc(name, params: params);
  static List<Map<String, dynamic>> rows(dynamic value) =>
      List<Map<String, dynamic>>.from(value as List);
  Future<List<Map<String, dynamic>>> inbox({
    String keyword = '',
    int offset = 0,
  }) async => rows(
    await _rpc('chat_inbox', {
      'p_keyword': keyword,
      'p_offset': offset,
      'p_limit': 30,
    }),
  );
  Future<List<Map<String, dynamic>>> blocked({
    String keyword = '',
    int offset = 0,
  }) async => rows(
    await _rpc('chat_blocked', {
      'p_keyword': keyword,
      'p_offset': offset,
      'p_limit': 30,
    }),
  );
  Future<List<Map<String, dynamic>>> search(String keyword) async => rows(
    await _rpc('chat_provider_search', {'p_keyword': keyword, 'p_limit': 30}),
  );
  Future<String> open({String? providerId, String? bookingId}) async =>
      (await _rpc('chat_open', {
            'p_provider_id': providerId,
            'p_booking_id': bookingId,
          }))
          as String;
  Future<Map<String, dynamic>> history(String id, {int? before}) async =>
      Map<String, dynamic>.from(
        await _rpc('chat_history', {
          'p_conversation_id': id,
          'p_before': before,
          'p_limit': 40,
        }),
      );
  Future<Map<String, dynamic>> send(
    String id,
    String body,
    String requestId,
  ) async => Map<String, dynamic>.from(
    await _rpc('chat_send', {
      'p_conversation_id': id,
      'p_body': body,
      'p_request_id': requestId,
    }),
  );
  Future<void> manage(String id, String action, {int? readThrough}) async =>
      _rpc('chat_manage', {
        'p_conversation_id': id,
        'p_action': action,
        'p_read_through': readThrough,
      });
}

/// Reconnect/resume refresh plus a bounded fallback when Realtime is unavailable.
class ChatUpdates extends WidgetsBindingObserver {
  final ChatService service;
  final Future<void> Function() refresh;
  final String? conversationId;
  RealtimeChannel? _channel;
  Timer? _debounce, _poll;
  bool _closed = false;
  ChatUpdates(this.service, this.refresh, {this.conversationId}) {
    if (!service.isLive) return;
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _schedule());
    unawaited(_subscribe());
  }
  Future<void> _subscribe() async {
    try {
      final identity = await service.client.rpc('account_identity');
      if (_closed) return;
      _channel = service.client
          .channel('chat-${identityHashCode(this)}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: conversationId == null ? 'chat_members' : 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: conversationId == null ? 'user_id' : 'conversation_id',
              value: conversationId ?? identity['user_id'],
            ),
            callback: (_) => _schedule(),
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) _schedule();
          });
    } catch (_) {
      /* Visible load/retry controls report connection failures. */
    }
  }

  void _schedule() {
    if (_closed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!_closed) unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule();
      _poll ??= Timer.periodic(const Duration(seconds: 20), (_) => _schedule());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void dispose() {
    _closed = true;
    _debounce?.cancel();
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) unawaited(service.client.removeChannel(_channel!));
  }
}
