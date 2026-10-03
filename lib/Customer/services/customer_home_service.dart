import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/account_access.dart';

class CustomerHomeService {
  final SupabaseClient _client;
  CustomerHomeService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getCategories() async {
    final rows = await _client
        .from('service_categories')
        .select('category_id,category_name,display_order')
        .eq('is_active', true)
        .order('display_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Actual verified providers with an available service, ordered by rating.
  /// Directory results are not personalised AI predictions.
  Future<List<Map<String, dynamic>>> getRecommendedProviders() async {
    final rows = await _client.rpc('customer_provider_directory');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> getCustomerHeaderData() async {
    final identity = await AccountAccess.requireRole(_client, 'customer');
    final profile = await _client
        .from('customer_profiles')
        .select('default_address')
        .eq('user_id', identity['user_id'])
        .single();
    final address = profile['default_address']?.toString().trim() ?? '';
    return {
      'name': identity['full_name'],
      'address': address.isEmpty ? 'Choose a service address' : address,
    };
  }
}
