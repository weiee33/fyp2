import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerReviewService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<String?> _getCustomerId() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row = await _client.from('customer_profiles').select('customer_id').eq('user_id', uid).maybeSingle();
    return row?['customer_id'] as String?;
  }

  /// FR-09: Verify if booking is eligible for a review (Must be 'Completed')[cite: 413, 452]
  Future<bool> verifyBookingEligibility(String bookingId) async {
    final cid = await _getCustomerId();
    if (cid == null) return false;

    // Check if booking belongs to customer, is completed, and has no existing review[cite: 452]
    final booking = await _client
        .from('bookings')
        .select('booking_status, reviews(review_id)')
        .eq('booking_id', bookingId)
        .eq('customer_id', cid)
        .maybeSingle();

    if (booking == null) return false;

    final status = booking['booking_status'];
    final existingReviews = booking['reviews'] as List?;

    // Only allow if status is Completed and no review exists yet[cite: 452]
    return status == 'Completed' && (existingReviews == null || existingReviews.isEmpty);
  }

  /// Upload optional review image to Supabase Storage
  Future<String> uploadReviewImage(Uint8List bytes, String fileExt, String bookingId) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');

    final path = 'reviews/${bookingId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    await _client.storage.from('reviews_bucket').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    return _client.storage.from('reviews_bucket').getPublicUrl(path);
  }

  /// Submit the closed-loop review
  Future<void> submitReview({
    required String bookingId,
    required String providerId,
    required int ratingScore,
    String? comment,
    String? imageUrl,
  }) async {
    final cid = await _getCustomerId();
    if (cid == null) throw Exception('Customer profile not found');

    await _client.from('reviews').insert({
      'booking_id': bookingId,
      'customer_id': cid,
      'provider_id': providerId,
      'rating_score': ratingScore,
      'review_comment': comment,
      'review_image_url': imageUrl,
      'is_verified_booking': true,
      'is_flagged': false,
      'moderation_status': 'visible'
    });
  }
}