import 'dart:typed_data';
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
  Future<Map<String, dynamic>> sendPhoto(
    String id,
    Uint8List bytes,
    String requestId,
  ) async {
    final mime = photoMime(bytes);
    final extension = mime == 'image/jpeg'
        ? 'jpg'
        : mime == 'image/png'
        ? 'png'
        : 'webp';
    final user = client.auth.currentUser;
    if (user == null) throw const FormatException('Please sign in again.');
    final path = '${user.id}/$id/$requestId.$extension';
    try {
      await client.storage
          .from('chat-photos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
    } on StorageException catch (error) {
      // Immutable path and retained request ID make retries safe after a lost response.
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
    }
    return Map<String, dynamic>.from(
      await _rpc('chat_send_photo', {
        'p_conversation_id': id,
        'p_path': path,
        'p_request_id': requestId,
      }),
    );
  }

  Future<Uint8List> photo(String path) =>
      client.storage.from('chat-photos').download(path);
  static String photoMime(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 5 MB.');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    throw const FormatException('Choose a JPEG, PNG or WebP photo.');
  }

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
