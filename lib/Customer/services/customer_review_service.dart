import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_image_service.dart';

class CustomerReviewService {
  final SupabaseClient _client;
  CustomerReviewService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<bool> verifyBookingEligibility(String bookingId) async =>
      await _client.rpc(
        'customer_review_eligibility',
        params: {'p_booking_id': bookingId},
      ) ==
      true;

  Future<String> uploadReviewImage(
    Uint8List bytes,
    String fileExt,
    String bookingId,
  ) => CustomerImageService(_client).upload(
    bucket: 'review-images',
    folder: 'reviews/$bookingId',
    bytes: bytes,
    extension: fileExt,
  );

  Future<void> submitReview({
    required String bookingId,
    required int ratingScore,
    String? comment,
    String? imageUrl,
  }) async {
    if (ratingScore < 1 || ratingScore > 5) {
      throw const FormatException('Choose a rating from 1 to 5 stars.');
    }
    await _client.rpc(
      'customer_submit_review',
      params: {
        'p_booking_id': bookingId,
        'p_rating': ratingScore,
        'p_comment': comment?.trim(),
        // Permanent object path in a private bucket, never an expiring signed URL.
        'p_image_url': imageUrl,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getMyReviews() async {
    final result = await _client.rpc('customer_my_reviews');
    return List<Map<String, dynamic>>.from(result as List);
  }

  Future<String> getImageUrl(String path) =>
      _client.storage.from('review-images').createSignedUrl(path, 600);
}
