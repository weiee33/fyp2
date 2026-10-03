import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/account_access.dart';
import 'customer_image_service.dart';

class CustomerProfileService {
  final SupabaseClient _client;
  CustomerProfileService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> getProfileData() async {
    final identity = await AccountAccess.requireRole(_client, 'customer');
    final user = await _client
        .from('users')
        .select('full_name, phone, email, profile_photo_url')
        .eq('user_id', identity['user_id'])
        .single();
    final profile = await _client
        .from('customer_profiles')
        .select('customer_id, service_preferences, default_address')
        .eq('user_id', identity['user_id'])
        .single();
    return {...user, ...profile};
  }

  Future<List<String>> getPreferenceOptions() async {
    final rows = await _client
        .from('service_categories')
        .select('category_name')
        .eq('is_active', true)
        .order('display_order');
    return rows.map((row) => row['category_name'].toString()).toList();
  }

  /// One transaction updates both user details and customer preferences.
  Future<void> updateProfile({
    required String fullName,
    required String phone,
    String? photoUrl,
    required List<String> preferences,
  }) async {
    await _client.rpc(
      'customer_profile_update',
      params: {
        'p_full_name': fullName.trim(),
        'p_phone': phone.trim(),
        'p_preferences': preferences.toSet().toList(),
        'p_photo_url': photoUrl,
      },
    );
  }

  Future<String> uploadAvatar(Uint8List bytes, String fileExt) async {
    final path = await CustomerImageService(_client).upload(
      bucket: 'profiles',
      folder: 'avatars',
      bytes: bytes,
      extension: fileExt,
    );
    return _client.storage.from('profiles').getPublicUrl(path);
  }
}
