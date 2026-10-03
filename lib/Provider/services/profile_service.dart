import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final _client = Supabase.instance.client;

  // ==================== Profile ====================

  Future<String?> getProviderId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('provider_profiles')
        .select('provider_id')
        .eq('user_id', uid)
        .maybeSingle();
    return row?['provider_id'] as String?;
  }

  /// Returns merged data from users + provider_profiles
  Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    final userRow = await _client
        .from('users')
        .select()
        .eq('user_id', uid)
        .maybeSingle();

    final providerRow = await _client
        .from('provider_profiles')
        .select()
        .eq('user_id', uid)
        .maybeSingle();

    if (userRow == null && providerRow == null) return null;

    return {
      ...?userRow,
      ...?providerRow,
    };
  }

  /// Updates users and provider_profiles separately
  Future<void> updateProfile(Map<String, dynamic> data) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    final userFields = <String, dynamic>{};
    final providerFields = <String, dynamic>{};

    const userKeys = {'full_name', 'phone', 'profile_photo_url'};
    const providerKeys = {
      'business_name',
      'bio',
      'years_experience',
      'city',
      'region',
      'service_radius_km',
      'verification_status',
    };

    data.forEach((key, value) {
      if (userKeys.contains(key)) userFields[key] = value;
      if (providerKeys.contains(key)) providerFields[key] = value;
    });

    if (userFields.isNotEmpty) {
      await _client.from('users').update(userFields).eq('user_id', uid);
    }

    if (providerFields.isNotEmpty) {
      final exists = await _client
          .from('provider_profiles')
          .select('provider_id')
          .eq('user_id', uid)
          .maybeSingle();

      if (exists == null) {
        await _client.from('provider_profiles').insert({
          'user_id': uid,
          'verification_status': 'Pending',
          ...providerFields,
        });
      } else {
        await _client
            .from('provider_profiles')
            .update(providerFields)
            .eq('user_id', uid);
      }
    }
  }

  // ==================== Storage ====================

  /// Upload avatar to 'profiles' bucket
  Future<String> uploadAvatar(Uint8List bytes, String fileExt) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not logged in');

    final path = '$uid/avatar.$fileExt';

    await _client.storage.from('profiles').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    final url = _client.storage.from('profiles').getPublicUrl(path);
    return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Generic file upload (for certifications, licenses, etc.)
  Future<String> uploadFile(
      String bucket,
      String path,
      Uint8List bytes,
      ) async {
    await _client.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  // ==================== Certifications ====================

  Future<List<Map<String, dynamic>>> getCertifications() async {
    final pid = await getProviderId();
    if (pid == null) return [];
    final res = await _client
        .from('provider_certifications')
        .select()
        .eq('provider_id', pid);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> addCertification(Map<String, dynamic> data) async {
    final pid = await getProviderId();
    if (pid == null) return;
    await _client
        .from('provider_certifications')
        .insert({...data, 'provider_id': pid});
  }

  // ✅ New: update an existing certification
  Future<void> updateCertification(
      String certificationId,
      Map<String, dynamic> data,
      ) async {
    await _client
        .from('provider_certifications')
        .update(data)
        .eq('certification_id', certificationId);
  }

  Future<void> deleteCertification(String certificationId) async {
    await _client
        .from('provider_certifications')
        .delete()
        .eq('certification_id', certificationId);
  }

  // ==================== Working Hours ====================

  Future<void> setWorkingHours(List<Map<String, dynamic>> rows) async {
    final pid = await getProviderId();
    if (pid == null) return;
    final withId =
    rows.map((r) => {...r, 'provider_id': pid}).toList(growable: false);

    // ✅ upsert with onConflict to prevent duplicate key errors
    await _client.from('provider_working_hours').upsert(
      withId,
      onConflict: 'provider_id,day_of_week',
    );
  }

  Future<List<Map<String, dynamic>>> getWorkingHours() async {
    final pid = await getProviderId();
    if (pid == null) return [];
    final res = await _client
        .from('provider_working_hours')
        .select()
        .eq('provider_id', pid)
        .order('day_of_week');
    return List<Map<String, dynamic>>.from(res);
  }
}