import 'package:fyp2/shared/localization/app_language.dart';
import '../../../shared/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import '../bookings/booking_detail_screen.dart';

class NotificationDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const NotificationDetailScreen({super.key, required this.data});

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final bookingId = data['booking_id']?.toString();
    final chatLink = data['deep_link']?.toString() ?? '';
    final type = data['notification_type']?.toString() ?? '';
    final color = _colorForType(type);
    final icon = _iconForType(type);

    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    // 判断是否是聊天消息
    final isChat = RegExp(r'^chat/[0-9a-fA-F-]{36}$').hasMatch(chatLink);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          tr('Notification Detail'),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        // 👇 使用 BookingDetailScreen 相同的物理效果
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Header Card ----
          Card(
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _borderOrange),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
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
                          tr(type.isEmpty ? 'Notification' : type),
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
                    tr(data['title']?.toString() ?? 'Notification'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Timestamp
                  Text(
                    _formatTime(data['created_at']?.toString(), isZh, isMs),
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
                  Text(
                    isZh
                        ? '消息内容'
                        : (isMs ? 'Mesej' : 'Message'),
                    style: const TextStyle(
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
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: _borderOrange),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _lightOrange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        color: _primaryOrange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isZh
                                ? '关联预约'
                                : (isMs
                                ? 'Tempahan Berkaitan'
                                : 'Related Booking'),
                            style: const TextStyle(
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
                              color: _primaryOrange,
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

          // ===== Action Buttons =====
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 聊天按钮 (放在上面)
              if (isChat)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConversationScreen(
                            customer: false,
                            conversationId: chatLink.substring(5),
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryOrange,
                        side: const BorderSide(color: _primaryOrange, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            isZh
                                ? '与客户聊天'
                                : (isMs
                                ? 'Sembang dengan Pelanggan'
                                : 'Chat with Customer'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 2. 查看预约按钮 (放在最下方)
              if (bookingId != null && bookingId.isNotEmpty)
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BookingDetailScreen(bookingId: bookingId),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      isZh
                          ? '查看预约详情'
                          : (isMs ? 'Lihat Tempahan' : 'View Booking'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // 👇 最关键的一步：加上 BookingDetail 末尾一模一样的 40 像素留白
          // 这样就能保证滑到底部时，按钮能被完整弹出来，且不会被系统手势条遮挡
          const SizedBox(height: 40),
        ],
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
        return _primaryOrange;
    }
  }

  String _formatTime(String? raw, bool isZh, bool isMs) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);

    if (diff.inMinutes < 1) {
      return isZh ? '刚刚' : (isMs ? 'Baru sahaja' : 'Just now');
    }
    if (diff.inMinutes < 60) {
      return isZh
          ? '${diff.inMinutes} 分钟前'
          : (isMs
          ? '${diff.inMinutes} minit lalu'
          : '${diff.inMinutes} min ago');
    }
    if (diff.inHours < 24) {
      return isZh
          ? '${diff.inHours} 小时前'
          : (isMs ? '${diff.inHours} jam lalu' : '${diff.inHours} hours ago');
    }
    if (diff.inDays < 7) {
      return isZh
          ? '${diff.inDays} 天前'
          : (isMs ? '${diff.inDays} hari lalu' : '${diff.inDays} days ago');
    }
    return '${d.day}/${d.month}/${d.year}';
  }
}