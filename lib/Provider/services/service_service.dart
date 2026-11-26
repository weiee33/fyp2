import '../../shared/account_access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceService {
  final _client = Supabase.instance.client;

  /// Fetches all active services for the currently logged-in provider.
  Future<List<Map<String, dynamic>>> getMyServices() async {
    final uid =
    (await AccountAccess.requireRole(_client, 'provider'))['user_id']
    as String;

    final res = await _client
        .from('services')
        .select('*, provider_profiles!inner(user_id)')
        .eq('provider_profiles.user_id', uid)
        .eq('is_active', true);

    return List<Map<String, dynamic>>.from(res);
  }

  /// Fetches all active service categories ordered by display order.
  Future<List<Map<String, dynamic>>> getCategories() async {
    final res = await _client
        .from('service_categories')
        .select()
        .eq('is_active', true)
        .order('display_order');

    return List<Map<String, dynamic>>.from(res);
  }

  /// Adds a new service record.
  Future<void> addService(Map<String, dynamic> data) async {
    await _client.from('services').insert(data);
  }

  /// Updates an existing service by ID.
  Future<void> updateService(String id, Map<String, dynamic> data) async {
    await _client.from('services').update(data).eq('service_id', id);
  }

  /// Soft deletes a service by setting `is_active` to false.
  Future<void> deleteService(String id) async {
    await _client
        .from('services')
        .update({'is_active': false})
        .eq('service_id', id);
  }

  /// Retrieves the `provider_id` from `provider_profiles` for the logged-in user.
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
}