import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_transaction_service.dart';

Uint8List _preparePhoto(Uint8List bytes) {
  if (bytes.length > 16 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 16 MB.');
  }
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Choose a supported photo.');
  final upright = image.bakeOrientation(decoded);
  final resized = upright.width > 1600 || upright.height > 1600
      ? image.copyResize(
          upright,
          width: upright.width >= upright.height ? 1600 : null,
          height: upright.height > upright.width ? 1600 : null,
        )
      : upright;
  // New JPEG contains pixels only, not source GPS/EXIF metadata.
  final pixels = image.Image.from(resized)..exif.clear();
  final result = Uint8List.fromList(image.encodeJpg(pixels, quality: 82));
  if (result.length > 4 * 1024 * 1024) {
    throw const FormatException('Choose a smaller photo.');
  }
  return result;
}

class CustomerAiService {
  final CustomerRpc? rpc;
  final CustomerRpc? invoke;
  CustomerAiService({this.rpc, this.invoke});
  SupabaseClient get client => Supabase.instance.client;
  Future<dynamic> _call(String name, Map<String, dynamic> p) =>
      rpc != null ? rpc!(name, p) : client.rpc(name, params: p);
  static List<Map<String, dynamic>> rows(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Future<List<Map<String, dynamic>>> conversations({int offset = 0}) async =>
      rows(
        await _call('customer_ai_conversations', {
          'p_limit': 30,
          'p_offset': offset,
        }),
      );
  Future<Map<String, dynamic>> create(String requestId) async =>
      Map<String, dynamic>.from(
        await _call('customer_ai_create_conversation', {
          'p_request_id': requestId,
        }),
      );
  Future<List<Map<String, dynamic>>> history(String id, {int? before}) async =>
      rows(
        await _call('customer_ai_messages', {
          'p_conversation_id': id,
          'p_before': before,
          'p_limit': 40,
        }),
      );
  Future<dynamic> _edge(Map<String, dynamic> body) async {
    try {
      final request = invoke != null
          ? invoke!('customer-assistant', body)
          : client.functions
                .invoke('customer-assistant', body: body)
                .then((response) => response.data);
      return await request.timeout(
        const Duration(seconds: 110),
        onTimeout: () => throw const FormatException(
          'The connection is taking too long. Your draft is kept; tap Retry.',
        ),
      );
    } on FunctionException catch (e) {
      final details = e.details;
      throw FormatException(
        details is Map
            ? details['error']?.toString() ??
                  'Assistant unavailable. Please retry.'
            : 'Assistant unavailable. Please retry.',
      );
    }
  }

  Future<void> rename(String id, String title) async {
    await _call('customer_ai_rename_conversation', {
      'p_conversation_id': id,
      'p_title': title,
    });
  }

  Future<Map<String, dynamic>> booking(String id) async =>
      Map<String, dynamic>.from(
        await _call('customer_booking_detail', {'p_booking_id': id}),
      );

  Future<void> delete(String id) async =>
      _edge({'operation': 'delete', 'conversation_id': id});
  Future<Map<String, dynamic>> send({
    required String conversation,
    required String requestId,
    required String message,
    required String mode,
    String? imagePath,
  }) async {
    final data = await _edge({
      'conversation_id': conversation,
      'request_id': requestId,
      'message': message,
      'mode': mode,
      if (imagePath != null) 'image_path': imagePath,
    });
    return Map<String, dynamic>.from(data['message'] as Map);
  }

  Future<Map<String, dynamic>> confirm(String action) async =>
      Map<String, dynamic>.from(
        await _call('customer_ai_confirm_action', {'p_action_id': action}),
      );
  Future<Uint8List> preparePhoto(Uint8List bytes) =>
      compute(_preparePhoto, bytes);
  Future<String> upload(
    String conversation,
    String requestId,
    Uint8List bytes,
  ) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw const FormatException('Sign in to attach a photo.');
    final path = '$uid/$conversation/$requestId.jpg';
    try {
      await client.storage
          .from('customer-ai-images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      if (e.statusCode != '409') rethrow;
    }
    return path;
  }

  Future<Uint8List> photo(String path) =>
      client.storage.from('customer-ai-images').download(path);
}
