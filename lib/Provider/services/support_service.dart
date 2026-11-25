import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/chat/chat_service.dart';

class ProviderSupportPhoto {
  final Uint8List bytes;
  final String mime;
  ProviderSupportPhoto(this.bytes) : mime = ChatService.photoMime(bytes);
}

class ProviderSupportService {
  final SupabaseClient? _client;
  ProviderSupportService({SupabaseClient? client}) : _client = client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> requests({
    String? id,
    int offset = 0,
  }) async {
    var query = client.from('provider_support_tickets').select();

    if (id != null) {
      query = query.eq('id', id);
    } else {
      final authId = client.auth.currentUser?.id;
      if (authId != null) {
        query = query.eq('provider_id', authId);
      }
    }

    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + 29)
        .timeout(const Duration(seconds: 30));

    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<String> send({
    required String requestId,
    String? bookingId,
    required String subject,
    required String description,
    required List<ProviderSupportPhoto> photos,
  }) async {
    if (photos.length > 3) throw const FormatException('Choose up to 3 photos.');
    final authId = client.auth.currentUser?.id;
    if (authId == null) throw const AuthException('Sign in to send a support request.');

    final insertRes = await client.from('provider_support_tickets').insert({
      'provider_id': authId,
      'subject': subject.trim(),
      'description': description.trim(),
      'status': 'Pending',
    }).select('id').single();

    final newId = insertRes['id'] as String;

    for (var i = 0; i < photos.length; i++) {
      try {
        await client.storage
            .from('support-photos')
            .uploadBinary(
          '$authId/$newId/$i',
          photos[i].bytes,
          fileOptions: FileOptions(contentType: photos[i].mime, upsert: false),
        )
            .timeout(const Duration(seconds: 60));
      } on StorageException catch (e) {
        if (e.statusCode != '409' && e.error != 'Duplicate') rethrow;
      }
    }

    return newId;
  }

  Future<String> photoUrl(String path) => client.storage
      .from('support-photos')
      .createSignedUrl(path, 300)
      .timeout(const Duration(seconds: 30));
}