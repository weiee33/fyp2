import 'package:intl/intl.dart';

/// Dates and times returned by the API use the service area's Malaysia time zone.
class CustomerBooking {
  final Map<String, dynamic> data;
  CustomerBooking.fromJson(Map<String, dynamic> json)
    : data = Map.unmodifiable(json);
  String get id => data['booking_id'] as String;
  String get providerId => data['provider_id'] as String;
  String get serviceName => data['service_name']?.toString() ?? 'Service';
  String get providerName =>
      data['business_name']?.toString() ?? 'Service provider';
  String get status => data['booking_status']?.toString() ?? 'Pending';
  String get date => data['booking_date']?.toString() ?? '';
  String get time =>
      (data['scheduled_time']?.toString() ?? '').split('.').first;
  String get appointmentLabel {
    final day = DateTime.tryParse(date);
    final parts = time.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length > 1 ? parts[1] : '';
    if (day == null || hour == null) return '$date · $time';
    return '${DateFormat('EEE, d MMM yyyy').format(day)} · ${hour % 12 == 0 ? 12 : hour % 12}:$minute ${hour >= 12 ? 'PM' : 'AM'}';
  }

  String get address => data['customer_address']?.toString() ?? '';
  double get amount => double.tryParse(data['total_amount'].toString()) ?? 0;
  DateTime? get paymentDeadline =>
      DateTime.tryParse(data['reservation_expires_at']?.toString() ?? '');
  bool get paymentWindowExpired =>
      !hasReceipt &&
      (data['reservation_expired'] == true ||
          (paymentDeadline != null &&
              !paymentDeadline!.isAfter(DateTime.now())));
  bool get appointmentPassed {
    final scheduled = DateTime.tryParse(
      data['scheduled_datetime']?.toString() ?? '',
    );
    return scheduled != null && !scheduled.isAfter(DateTime.now());
  }

  bool get needsNewBooking =>
      !hasReceipt &&
      (status == 'Pending' || status == 'Confirmed') &&
      (paymentWindowExpired || appointmentPassed);
  String get displayStatus => needsNewBooking ? 'Expired' : status;
  bool get canPay =>
      data['can_pay'] == true &&
      !hasReceipt &&
      !paymentWindowExpired &&
      !appointmentPassed;
  bool get canCancel => data['can_cancel'] == true;
  bool get canReview => data['can_review'] == true;
  bool get hasReview => data['has_review'] == true;
  Map<String, dynamic>? get payment => data['payment'] is Map
      ? Map<String, dynamic>.from(data['payment'] as Map)
      : null;
  String get paymentStatus =>
      payment?['payment_status']?.toString() ?? 'Not paid';
  bool get hasReceipt =>
      paymentStatus == 'Success' || paymentStatus == 'Refunded';
  String get shortId =>
      '#${id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase()}';
}

class BookingSlot {
  final String time;
  final String? datetime;
  BookingSlot.fromJson(Map<String, dynamic> json)
    : time = json['scheduled_time'] as String,
      datetime = json['scheduled_datetime'] as String?;
  String get label {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    return '${hour % 12 == 0 ? 12 : hour % 12}:${parts[1]} ${hour >= 12 ? 'PM' : 'AM'}';
  }
}

class CheckoutSession {
  final Uri url;
  final bool testMode;
  CheckoutSession._(this.url, this.testMode);
  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    final url = Uri.tryParse(json['checkout_url']?.toString() ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'checkout.stripe.com' ||
        (url.hasPort && url.port != 443) ||
        url.userInfo.isNotEmpty) {
      throw const FormatException(
        'The payment gateway returned an invalid checkout URL.',
      );
    }
    return CheckoutSession._(url, json['test_mode'] == true);
  }
}
