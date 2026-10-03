import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import 'notification_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _filter = 'All';

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final items = await _service.getMyNotifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Failed to load: $e');
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'All') return _items;
    return _items.where((n) {
      final type = n['notification_type']?.toString() ?? '';
      if (_filter == 'Bookings') {
        return type == 'New Booking' || type == 'Cancellation';
      }
      if (_filter == 'Messages') return type == 'Message';
      if (_filter == 'Payments') return type == 'Payment';
      return true;
    }).toList();
  }

  Future<void> _openDetail(Map<String, dynamic> n) async {
    if (n['is_read'] != true) {
      try {
        await _service.markAsRead(n['notification_id']);
        if (!mounted) return;
        setState(() => n['is_read'] = true);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationDetailScreen(data: n),
      ),
    );
    _load();
  }

  Future<void> _delete(String id) async {
    try {
      await _service.deleteNotification(id);
      if (!mounted) return;
      setState(() =>
          _items.removeWhere((n) => n['notification_id'].toString() == id));
      _showSuccess('Notification deleted');
    } catch (e) {
      _showError('Delete failed: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: Column(
          children: [
            // ---- Filter Tabs ----
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('All'),
                    const SizedBox(width: 8),
                    _filterChip('Bookings'),
                    const SizedBox(width: 8),
                    _filterChip('Messages'),
                    const SizedBox(width: 8),
                    _filterChip('Payments'),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // ---- List ----
            Expanded(
              child: list.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                onRefresh: _load,
                color: _primaryColor,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (_, i) =>
                      _notificationTile(list[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label) {
    final selected = _filter == label;
    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _primaryColor : const Color(0xFFEEF2F8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _primaryColor,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _notificationTile(Map<String, dynamic> n) {
    final isRead = n['is_read'] == true;
    final type = n['notification_type']?.toString() ?? '';
    final icon = _iconForType(type);
    final color = _colorForType(type);

    return Dismissible(
      key: ValueKey(n['notification_id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _delete(n['notification_id'].toString()),
      child: Card(
        elevation: isRead ? 0 : 1,
        margin: const EdgeInsets.only(bottom: 10),
        color: isRead ? const Color(0xFFF8FAFC) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isRead
                ? Colors.transparent
                : color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () => _openDetail(n),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n['title']?.toString() ?? 'Notification',
                              style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n['message']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(n['created_at']?.toString()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No notifications',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Updates about bookings, payments and messages will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
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
}