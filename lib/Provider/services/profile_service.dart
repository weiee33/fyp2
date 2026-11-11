import '../../shared/account_access.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final _client = Supabase.instance.client;

  // ==================== Profile ====================

  Future<String?> getProviderId() async {
    final uid =
    (await AccountAccess.requireRole(_client, 'provider'))['user_id']
    as String;
    final row = await _client
        .from('provider_profiles')
        .select('provider_id')
        .eq('user_id', uid)
        .maybeSingle();
    return row?['provider_id'] as String?;
  }

  Future<Map<String, dynamic>?> getMyProfile() async {
    final uid =
    (await AccountAccess.requireRole(_client, 'provider'))['user_id']
    as String;

    final userRow = await _client
        .from('users')
        .select('user_id,full_name,phone,email,profile_photo_url')
        .eq('user_id', uid)
        .maybeSingle();

    final providerRow = await _client
        .from('provider_profiles')
        .select(
      'provider_id,user_id,business_name,bio,years_experience,verification_status,overall_rating,total_reviews,service_radius_km,region,city,service_latitude,service_longitude',
    )
        .eq('user_id', uid)
        .maybeSingle();

    if (userRow == null && providerRow == null) return null;

    return {...?userRow, ...?providerRow};
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final uid =
    (await AccountAccess.requireRole(_client, 'provider'))['user_id']
    as String;

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
      'service_latitude',
      'service_longitude',
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
        throw const AuthException(
          'Your provider profile is not available. Please contact an administrator.',
        );
      }
      await _client
          .from('provider_profiles')
          .update(providerFields)
          .eq('user_id', uid);
    }
  }

  // ==================== Storage ====================

  Future<String> uploadAvatar(Uint8List bytes, String fileExt) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not logged in');

    final path = '$uid/avatar.$fileExt';

    await _client.storage
        .from('profiles')
        .uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    final url = _client.storage.from('profiles').getPublicUrl(path);
    return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> uploadFile(String bucket, String path, Uint8List bytes) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
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
    await _client.from('provider_certifications').insert({
      ...data,
      'provider_id': pid,
    });
  }

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
    final withId = rows
        .map((r) => {...r, 'provider_id': pid})
        .toList(growable: false);

    await _client
        .from('provider_working_hours')
        .upsert(withId, onConflict: 'provider_id,day_of_week');
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

  // ==================== Reviews ====================

  Future<List<Map<String, dynamic>>> getMyReviews() async {
    final pid = await getProviderId();
    if (pid == null) return [];

    // 1. 一次性查出 reviews，并且利用 !inner 强关联 customer_profiles
    // 很多 Supabase 拦截问题都是因为分步查导致的，一次性查最稳
    final rows = await _client
        .from('reviews')
        .select('''
          *,
          customer_profiles!inner (
            user_id,
            users!inner (
              full_name,
              profile_photo_url
            )
          )
        ''')
        .eq('provider_id', pid)
        .eq('moderation_status', 'visible')
        .order('created_at', ascending: false);

    final list = List<Map<String, dynamic>>.from(rows);

    // 2. 把查到的数据拍平，方便 UI 读取
    return list.map((r) {
      final profile = r['customer_profiles'];
      dynamic userInfo;

      if (profile is Map) {
        userInfo = profile['users'];
      }

      return {
        ...r,
        'customer': userInfo,
      };
    }).toList();
  }
}