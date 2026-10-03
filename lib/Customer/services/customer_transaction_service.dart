import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_model.dart';

typedef CustomerRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> params);

/// All identity, availability, price and state transitions are owned by the server.
class CustomerTransactionService {
  final SupabaseClient? _client;
  final CustomerRpc? _rpcOverride;
  final CustomerRpc? _functionOverride;
  CustomerTransactionService({
    SupabaseClient? client,
    CustomerRpc? rpc,
    CustomerRpc? invoke,
  }) : _client = client,
       _rpcOverride = rpc,
       _functionOverride = invoke;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  bool get usesLiveBackend => _rpcOverride == null;
  Future<dynamic> _rpc(String name, Map<String, dynamic> params) async =>
      _rpcOverride != null
      ? await _rpcOverride(name, params)
      : await client.rpc(name, params: params);

  /// Keep the token when retrying after a lost response.
  static String newRequestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<BookingSlot>> getAvailableTimeSlots({
    required String serviceId,
    required DateTime date,
  }) async {
    final result = await _rpc('customer_booking_slots', {
      'p_service_id': serviceId,
      'p_date': dateOnly(date),
    });
    return (result as List)
        .map(
          (row) => BookingSlot.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<CustomerBooking> createPendingBooking({
    required String serviceId,
    required String addressId,
    required DateTime date,
    required String scheduledTime,
    required String requestId,
    String? specialInstructions,
    String urgency = 'Medium',
  }) async {
    final result = await _rpc('customer_create_booking', {
      'p_service_id': serviceId,
      'p_address_id': addressId,
      'p_booking_date': dateOnly(date),
      'p_scheduled_time': scheduledTime,
      'p_special_instructions': specialInstructions,
      'p_urgency': urgency,
      'p_request_id': requestId,
    });
    return CustomerBooking.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<List<CustomerBooking>> getBookings({
    int offset = 0,
    int limit = 20,
  }) async {
    final result = await _rpc('customer_bookings', {
      'p_limit': limit,
      'p_offset': offset,
    });
    return (result as List)
        .map(
          (row) =>
              CustomerBooking.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<CustomerBooking> getBooking(String bookingId) async =>
      CustomerBooking.fromJson(
        Map<String, dynamic>.from(
          await _rpc('customer_booking_detail', {'p_booking_id': bookingId})
              as Map,
        ),
      );
  Future<CustomerBooking> cancelBooking(
    String bookingId,
    String reason,
  ) async => CustomerBooking.fromJson(
    Map<String, dynamic>.from(
      await _rpc('customer_cancel_booking', {
            'p_booking_id': bookingId,
            'p_reason': reason,
          })
          as Map,
    ),
  );
  Future<Map<String, dynamic>> getReceipt(String bookingId) async =>
      Map<String, dynamic>.from(
        await _rpc('customer_booking_receipt', {'p_booking_id': bookingId})
            as Map,
      );

  /// A browser URL is never evidence of a successful payment.
  Future<void> requestSupport(
    String bookingId,
    String subject,
    String description,
  ) async {
    await _rpc('customer_open_dispute', {
      'p_booking_id': bookingId,
      'p_subject': subject,
      'p_description': description,
    });
  }

  /// A browser URL is never evidence of a successful payment.
  Future<CheckoutSession> startCheckout(String bookingId) async {
    final data = _functionOverride != null
        ? await _functionOverride('customer-checkout', {
            'booking_id': bookingId,
          })
        : (await client.functions.invoke(
            'customer-checkout',
            body: {'booking_id': bookingId},
          )).data;
    return CheckoutSession.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

String bookingError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is FunctionException && error.details is Map) {
    final message = (error.details as Map)['error'];
    if (message is String && message.isNotEmpty) return message;
  }
  return 'Unable to complete the request. Check your connection and try again.';
}
