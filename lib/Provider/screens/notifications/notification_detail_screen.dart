import 'package:flutter/material.dart';
import '../bookings/booking_detail_screen.dart';

class NotificationDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const NotificationDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final bookingId = data['booking_id'];
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Detail')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['title'] ?? '',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(data['message'] ?? ''),
            const SizedBox(height: 8),
            if (bookingId != null)
              Text('Related Booking: #${bookingId.toString().substring(0, 8)}',
                  style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (bookingId != null)
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingDetailScreen(bookingId: bookingId),
                  ),
                ),
                child: const Text('View Booking'),
              ),
          ],
        ),
      ),
    );
  }
}