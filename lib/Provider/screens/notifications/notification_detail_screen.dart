import 'package:flutter/material.dart';
import '../bookings/booking_detail_screen.dart';

class NotificationDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const NotificationDetailScreen({super.key, required this.data});

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final bookingId = data['booking_id']?.toString();
    final type = data['notification_type']?.toString() ?? '';
    final color = _colorForType(type);
    final icon = _iconForType(type);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Notification Detail'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Header Card ----
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 14, color: color),
                            const SizedBox(width: 6),
                            Text(
                              type.isEmpty ? 'Notification' : type,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Title
                      Text(
                        data['title']?.toString() ?? 'Notification',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Timestamp
                      Text(
                        _formatTime(data['created_at']?.toString()),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Divider
                      const Divider(height: 1),
                      const SizedBox(height: 20),

                      // Message
                      const Text(
                        'Message',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data['message']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---- Related Booking Card ----
              if (bookingId != null && bookingId.isNotEmpty)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.receipt_long_outlined,
                            color: _primaryColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Related Booking',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '#${bookingId.length >= 8 ? bookingId.substring(0, 8) : bookingId}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // ---- View Booking Button ----
              if (bookingId != null && bookingId.isNotEmpty)
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BookingDetailScreen(bookingId: bookingId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text(
                      'View Booking',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'New Booking':
        return Icons.event_available;
      case 'Cancellation':
        return Icons.event_busy;
      case 'Payment':
        return Icons.payments_outlined;
      case 'Message':
        return Icons.message_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'New Booking':
        return const Color(0xFF3B82F6);
      case 'Cancellation':
        return const Color(0xFFEF4444);
      case 'Payment':
        return const Color(0xFF10B981);
      case 'Message':
        return const Color(0xFF8B5CF6);
      default:
        return _primaryColor;
    }
  }

  String _formatTime(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}