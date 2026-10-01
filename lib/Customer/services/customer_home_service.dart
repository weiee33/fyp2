import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerHomeService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// Fetch active service categories from Supabase
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final res = await _client
          .from('service_categories')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      if ((res as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(res);
      }
    } catch (_) {
      // Fallback below if table is empty
    }

    // Default categories matching Chapter 4 mockup
    return [
      {'category_name': 'Plumbing', 'icon': 'water_drop_rounded', 'color': 0xFF2563EB},
      {'category_name': 'Electrical', 'icon': 'bolt_rounded', 'color': 0xFFEAB308},
      {'category_name': 'Cleaning', 'icon': 'cleaning_services_rounded', 'color': 0xFF10B981},
      {'category_name': 'Aircon', 'icon': 'ac_unit_rounded', 'color': 0xFF06B6D4},
    ];
  }

  /// Fetch verified service providers for the AI Recommended carousel
  Future<List<Map<String, dynamic>>> getRecommendedProviders() async {
    try {
      final res = await _client
          .from('provider_profiles')
          .select('''
            provider_id,
            business_name,
            bio,
            overall_rating,
            total_reviews,
            verification_status,
            users!inner (
              full_name,
              profile_photo_url,
              phone
            ),
            services (
              service_id,
              service_name,
              base_price
            )
          ''')
          .eq('verification_status', 'Verified')
          .order('overall_rating', ascending: false)
          .limit(5);

      if ((res as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(res);
      }
    } catch (_) {
      // Fallback mock data below
    }

    // High-fidelity fallback matching Chapter 4 mockup
    return [
      {
        'provider_id': 'demo-1',
        'business_name': 'Ahmad Plumbers',
        'full_name': 'Ahmad Razak',
        'overall_rating': 4.9,
        'total_reviews': 124,
        'total_jobs': 340,
        'base_price': 80.00,
        'service_name': 'Pipe Repair & Unclogging',
        'match_tag': '98% Match • Nearest to You',
        'image_url': 'https://images.unsplash.com/photo-1540569014015-19a7be504e3a?w=400',
        'is_verified': true,
      },
      {
        'provider_id': 'demo-2',
        'business_name': 'BinaTech Electrical',
        'full_name': 'Lim Jian Wei',
        'overall_rating': 4.8,
        'total_reviews': 96,
        'total_jobs': 210,
        'base_price': 90.00,
        'service_name': 'Wiring & Circuit Inspection',
        'match_tag': '94% Match • High Reliability',
        'image_url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
        'is_verified': true,
      },
      {
        'provider_id': 'demo-3',
        'business_name': 'CleanPro Express',
        'full_name': 'Siti Nurhaliza',
        'overall_rating': 4.9,
        'total_reviews': 180,
        'total_jobs': 450,
        'base_price': 60.00,
        'service_name': 'Deep Home Sanitization',
        'match_tag': '92% Match • Top Rated Cleaner',
        'image_url': 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400',
        'is_verified': true,
      },
    ];
  }

  /// Get current user display profile
  Future<Map<String, dynamic>> getCustomerHeaderData() async {
    final user = currentUser;
    String name = 'Valued Customer';
    String address = 'KL City Center, Kuala Lumpur';

    if (user != null) {
      if (user.userMetadata?['full_name'] != null) {
        name = user.userMetadata!['full_name'];
      }
      try {
        final profile = await _client
            .from('customer_profiles')
            .select('default_address')
            .eq('user_id', user.id)
            .maybeSingle();
        if (profile?['default_address'] != null && profile!['default_address'].toString().isNotEmpty) {
          address = profile['default_address'];
        }
      } catch (_) {}
    }

    return {'name': name, 'address': address};
  }
}