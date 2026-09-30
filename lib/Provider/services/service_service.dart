import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceService {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getMyServices() async {
    final uid = _client.auth.currentUser!.id;
    final res = await _client
        .from('services')
        .select('*, provider_profiles!inner(user_id)')
        .eq('provider_profiles.user_id', uid)
        .eq('is_active', true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final res = await _client
        .from('service_categories')
        .select()
        .eq('is_active', true)
        .order('display_order');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> addService(Map<String, dynamic> data) async {
    await _client.from('services').insert(data);
  }

  Future<void> updateService(String id, Map<String, dynamic> data) async {
    await _client.from('services').update(data).eq('service_id', id);
  }

  Future<void> deleteService(String id) async {
    await _client
        .from('services')
        .update({'is_active': false}).eq('service_id', id);
  }

  Future<String?> getProviderId() async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('provider_profiles')
        .select('provider_id')
        .eq('user_id', uid)
        .maybeSingle();
    return row?['provider_id'] as String?;
  }
}