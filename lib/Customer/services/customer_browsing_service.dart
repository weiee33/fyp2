import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_item.dart';

class CustomerBrowsingService {
  final SupabaseClient _client;

  CustomerBrowsingService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// The server filters verified, active providers and returns only public data.
  /// Offset pagination uses the server's deterministic service ordering.
  Future<List<ServiceItem>> searchServices({
    String? categoryId,
    String? categoryName,
    String? keyword,
    String? city,
    double? maxPrice,
    double? minRating,
    int limit = 21,
    int offset = 0,
  }) async {
    final rows = await _client.rpc(
      'customer_search_services',
      params: {
        'p_category_id': categoryId,
        'p_category_name': categoryName,
        'p_keyword': keyword?.trim(),
        'p_city': city?.trim(),
        'p_max_price': maxPrice,
        'p_min_rating': minRating,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return (rows as List)
        .map((row) => ServiceItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Map<String, dynamic>?> getProviderDetails(String providerId) async {
    final result = await _client.rpc(
      'customer_provider_details',
      params: {'p_provider_id': providerId},
    );
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }
}
