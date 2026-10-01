import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerProfileService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// Fetch combined user and customer_profile data
  Future<Map<String, dynamic>?> getProfileData() async {
    final uid = currentUser?.id;
    if (uid == null) return null;

    // Fetch from users table
    final userRow = await _client
        .from('users')
        .select('full_name, phone, email, profile_photo_url')
        .eq('user_id', uid)
        .maybeSingle();

    // Fetch from customer_profiles table
    final customerRow = await _client
        .from('customer_profiles')
        .select('customer_id, service_preferences, default_address')
        .eq('user_id', uid)
        .maybeSingle();

    if (userRow == null) return null;

    return {
      ...userRow,
      if (customerRow != null) ...customerRow,
    };
  }

  /// Update personal details and preference tags
  Future<void> updateProfile({
    required String fullName,
    required String phone,
    String? photoUrl,
    required List<String> preferences,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('User not logged in');

    // 1. Update public.users
    await _client.from('users').update({
      'full_name': fullName.trim(),
      'phone': phone.trim(),
      if (photoUrl != null) 'profile_photo_url': photoUrl,
    }).eq('user_id', uid);

    // 2. Update public.customer_profiles (Preference Tags)
    await _client.from('customer_profiles').update({
      'service_preferences': preferences,
    }).eq('user_id', uid);
  }

  /// Upload Avatar to Supabase Storage
  Future<String> uploadAvatar(Uint8List bytes, String fileExt) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('User not logged in');

    final path = 'customer_$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    await _client.storage.from('profiles').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    final url = _client.storage.from('profiles').getPublicUrl(path);
    // Append timestamp to bust cache
    return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
  }
}