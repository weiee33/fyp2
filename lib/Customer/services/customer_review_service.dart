import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_image_service.dart';
import 'customer_transaction_service.dart';

class CustomerReviewService {
  final SupabaseClient? _providedClient;
  final CustomerRpc? rpc;
  CustomerReviewService({SupabaseClient? client, this.rpc})
    : _providedClient = client;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;
  Future<dynamic> _call(String name, Map<String, dynamic> params) =>
      rpc != null ? rpc!(name, params) : _client.rpc(name, params: params);
  Future<List<Map<String, dynamic>>> getReadyToReview({int offset = 0}) async =>
      List<Map<String, dynamic>>.from(
        await _call('customer_review_queue', {
              'p_offset': offset,
              'p_limit': 20,
            })
            as List,
      );

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
    final result = await _call('customer_my_reviews', {});
    return List<Map<String, dynamic>>.from(result as List);
  }

  Future<String> getImageUrl(String path) =>
      _client.storage.from('review-images').createSignedUrl(path, 600);
}
