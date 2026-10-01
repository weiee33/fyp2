import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerBrowsingService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetches services matching search and filter criteria[cite: 378, 413]
  Future<List<Map<String, dynamic>>> searchServices({
    String? categoryId,
    String? categoryName,
    String? keyword,
    double? maxPrice,
    double? minRating,
  }) async {
    var query = _client.from('services').select('''
      service_id,
      service_name,
      description,
      base_price,
      estimated_duration,
      provider_profiles!inner (
        provider_id,
        business_name,
        overall_rating,
        total_reviews,
        verification_status,
        users!inner (
          profile_photo_url
        )
      ),
      service_categories!inner (
        category_name
      )
    ''').eq('is_active', true);

    // Apply Filters
    if (categoryName != null && categoryName.isNotEmpty) {
      query = query.eq('service_categories.category_name', categoryName);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      query = query.ilike('service_name', '%${keyword.trim()}%');
    }
    if (maxPrice != null) {
      query = query.lte('base_price', maxPrice);
    }
    if (minRating != null) {
      query = query.gte('provider_profiles.overall_rating', minRating);
    }

    final res = await query;
    return List<Map<String, dynamic>>.from(res);
  }

  /// Fetches comprehensive provider details[cite: 378]
  Future<Map<String, dynamic>?> getProviderDetails(String providerId) async {
    final res = await _client.from('provider_profiles').select('''
      *,
      users (full_name, profile_photo_url, phone),
      services (*),
      provider_certifications (certification_name, issuer, is_verified),
      reviews (
        rating_score, 
        review_comment, 
        created_at, 
        customer_profiles (users (full_name))
      )
    ''').eq('provider_id', providerId).maybeSingle();

    return res;
  }
}