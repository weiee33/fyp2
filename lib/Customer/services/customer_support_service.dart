import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/chat/chat_service.dart';

class SupportPhoto {
  final Uint8List bytes;
  final String mime;
  SupportPhoto(this.bytes) : mime = ChatService.photoMime(bytes);
}

class CustomerSupportService {
  final SupabaseClient? _client;
  CustomerSupportService({SupabaseClient? client}) : _client = client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> requests({
    String? id,
    int offset = 0,
  }) async {
    final rows = await client
        .rpc(
          'customer_support_requests',
          params: {'p_id': id, 'p_limit': 30, 'p_offset': offset},
        )
        .timeout(const Duration(seconds: 30));
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<String> send({
    required String requestId,
    String? bookingId,
    required String subject,
    required String description,
    required List<SupportPhoto> photos,
  }) async {
    if (photos.length > 3) {
      throw const FormatException('Choose up to 3 photos.');
    }
    final authId = client.auth.currentUser?.id;
    if (authId == null) {
      throw const AuthException('Sign in to send a support request.');
    }
    final prepared = await client
        .rpc(
          'customer_prepare_support',
          params: {
            'p_request_id': requestId,
            'p_booking_id': bookingId,
            'p_subject': subject.trim(),
            'p_description': description.trim(),
            'p_photo_count': photos.length,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (prepared['dispute_id'] != null) return prepared['dispute_id'] as String;
    for (var i = 0; i < photos.length; i++) {
      try {
        await client.storage
            .from('support-photos')
            .uploadBinary(
              '$authId/$requestId/$i',
              photos[i].bytes,
              fileOptions: FileOptions(
                contentType: photos[i].mime,
                upsert: false,
              ),
            )
            .timeout(const Duration(seconds: 60));
      } on StorageException catch (e) {
        // Immutable objects from the same reserved request survive network retries.
        if (e.statusCode != '409' && e.error != 'Duplicate') rethrow;
      }
    }
    final result = await client
        .rpc('customer_submit_support', params: {'p_request_id': requestId})
        .timeout(const Duration(seconds: 30));
    return result['dispute_id'] as String;
  }

  Future<String> photoUrl(String path) => client.storage
      .from('support-photos')
      .createSignedUrl(path, 300)
      .timeout(const Duration(seconds: 30));
}
