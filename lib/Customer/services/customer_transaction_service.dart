import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerTransactionService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<String?> _getCustomerId() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row = await _client.from('customer_profiles').select('customer_id').eq('user_id', uid).maybeSingle();
    return row?['customer_id'] as String?;
  }

  /// Generate available time slots (Mocked for prototype, ready for DB integration)
  List<String> getAvailableTimeSlots(DateTime date) {
    // In a full implementation, this queries 'provider_working_hours' and subtracts existing 'bookings'
    return ['09:00 AM', '11:30 AM', '02:00 PM', '04:30 PM'];
  }

  /// FR-07: Creates a Pending Booking[cite: 413, 447]
  Future<Map<String, dynamic>> createPendingBooking({
    required String providerId,
    required String serviceId,
    required DateTime date,
    required String timeString,
    required double totalAmount,
    String? specialInstructions,
    String urgency = 'Medium',
  }) async {
    final customerId = await _getCustomerId();
    if (customerId == null) throw Exception('Customer profile not found');

    // Fetch customer's default address for the snapshot
    final profile = await _client.from('customer_profiles').select('default_address').eq('customer_id', customerId).single();
    final address = profile['default_address'] ?? 'Address not set';

    // Parse timeString to PostgREST format
    final isPM = timeString.contains('PM');
    final timeParts = timeString.split(' ')[0].split(':');
    int hour = int.parse(timeParts[0]);
    if (isPM && hour != 12) hour += 12;
    if (!isPM && hour == 12) hour = 0;

    final scheduledDate = DateTime(date.year, date.month, date.day);
    final scheduledDatetime = DateTime(date.year, date.month, date.day, hour, int.parse(timeParts[1]));

    final response = await _client.from('bookings').insert({
      'customer_id': customerId,
      'provider_id': providerId,
      'service_id': serviceId,
      'booking_date': scheduledDate.toIso8601String().split('T')[0],
      'scheduled_time': '${hour.toString().padLeft(2, '0')}:${timeParts[1]}:00',
      'scheduled_datetime': scheduledDatetime.toIso8601String(),
      'customer_address': address,
      'special_instructions': specialInstructions,
      'urgency': urgency,
      'booking_status': 'Pending',
      'total_amount': totalAmount,
    }).select().single();

    return response;
  }

  /// FR-08: Process FPX Sandbox Payment and Secure Escrow[cite: 413, 449]
  Future<Map<String, dynamic>> processFpxPayment({
    required String bookingId,
    required double amount,
    required String bankName,
  }) async {
    final customerId = await _getCustomerId();
    if (customerId == null) throw Exception('Customer profile not found');

    // Generate Mock FPX Reference
    final fpxRef = 'FPX${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(9999)}';

    // 1. Insert Payment Record
    final payment = await _client.from('payments').insert({
      'booking_id': bookingId,
      'customer_id': customerId,
      'fpx_transaction_ref': fpxRef,
      'payment_method': 'FPX',
      'payment_amount': amount,
      'payment_status': 'Success',
      'escrow_held': true, // Escrow mechanism triggered
    }).select().single();

    // 2. Update Booking Status to Confirmed
    await _client.from('bookings').update({
      'booking_status': 'Confirmed',
    }).eq('booking_id', bookingId);

    return payment;
  }
}