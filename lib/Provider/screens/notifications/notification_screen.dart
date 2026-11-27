import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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
  final Set<String> _busy = {};

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  // 过滤器列表
  final List<String> _filters = ['All', 'Bookings', 'Messages', 'Payments'];

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
      _showAppDialog(
        title: 'Error',
        message: 'Failed to load notifications. Please retry.',
        isError: true,
      );
    }
  }

  // ============= Pop-up Box 弹窗 =============
  void _showAppDialog({required String title, required String message, required bool isError}) {
    showDialog(
      context: context,
      builder: (ctx) {
        final lang = Localizations.localeOf(context).languageCode;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isError ? Colors.red.shade50 : Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: isError ? Colors.red.shade600 : Colors.green.shade600,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      lang == 'zh' ? '知道了' : (lang == 'ms' ? 'OK' : 'OK'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
      MaterialPageRoute(builder: (_) => NotificationDetailScreen(data: n)),
    );
    _load();
  }

  Future<void> _delete(String id) async {
    if (!_busy.add(id)) return;
    try {
      await _service.deleteNotification(id);
      if (!mounted) return;
      setState(() => _items.removeWhere((n) => n['notification_id'].toString() == id));
      _showAppDialog(
        title: 'Success',
        message: 'Notification deleted.',
        isError: false,
      );
    } catch (e) {
      _showAppDialog(
        title: 'Error',
        message: 'Delete failed: $e',
        isError: true,
      );
    } finally {
      _busy.remove(id);
    }
  }

  String _formatTime(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return '';

    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) {
      return isZh ? '刚刚' : (isMs ? 'Baru sahaja' : 'Just now');
    }
    if (diff.inMinutes < 60) {
      return isZh
          ? '${diff.inMinutes} 分钟前'
          : (isMs ? '${diff.inMinutes} minit lalu' : '${diff.inMinutes} min ago');
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

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final list = _filtered;

    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isZh ? '通知' : (isMs ? 'Pemberitahuan' : 'Notifications'),
          // 👇 强制指定白色
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 👇 固定的横向滚动胶囊标签
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: _buildFilterCarousel(isZh, isMs),
            ),
            const Divider(height: 1),

            // 👇 列表部分（带有弹性效果）
            Expanded(
              child: _loading
                  ? const Center(
                child: CircularProgressIndicator(color: _primaryOrange),
              )
                  : list.isEmpty
                  ? _buildEmpty(isZh, isMs)
                  : RefreshIndicator(
                onRefresh: _load,
                color: _primaryOrange,
                child: ListView.builder(
                  // 👇 弹性物理效果
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _notificationTile(list[i], isZh, isMs),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 横向滚动的胶囊标签 (和 MyBookings 类似)
  Widget _buildFilterCarousel(bool isZh, bool isMs) {
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: List.generate(_filters.length, (index) {
            final filter = _filters[index];
            final isSelected = _filter == filter;
            String label = filter;

            if (filter == 'All') label = isZh ? '全部' : (isMs ? 'Semua' : 'All');
            if (filter == 'Bookings') label = isZh ? '预约' : (isMs ? 'Tempahan' : 'Bookings');
            if (filter == 'Messages') label = isZh ? '消息' : (isMs ? 'Mesej' : 'Messages');
            if (filter == 'Payments') label = isZh ? '付款' : (isMs ? 'Bayaran' : 'Payments');

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _filter = filter);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryOrange : _lightOrange,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? _primaryOrange : _borderOrange,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _primaryOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // 滑动操作卡片
  Widget _notificationTile(Map<String, dynamic> n, bool isZh, bool isMs) {
    final String id = n['notification_id'].toString();
    final bool isRead = n['is_read'] == true;
    final String type = n['notification_type']?.toString() ?? '';

    // 纯图标（无圆圈背景）
    final IconData icon = _iconForType(type);
    final Color color = _colorForType(type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Slidable(
          key: ValueKey(id),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.35,
            children: [
              SlidableAction(
                borderRadius: BorderRadius.circular(16),
                onPressed: (_) => _delete(id),
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                icon: Icons.delete_outline,
                label: isZh ? '删除' : (isMs ? 'Padam' : 'Delete'),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _openDetail(n),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isRead ? Colors.white : _lightOrange,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isRead ? _borderOrange : color.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 纯图标
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 16),

                  // 内容
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                n['title']?.toString() ?? 'Notification',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(n['created_at']?.toString()),
                              style: TextStyle(
                                fontSize: 11,
                                color: isRead ? Colors.grey : _primaryOrange,
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          n['message']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: isRead ? Colors.grey.shade600 : Colors.black87,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // 未读小圆点
                  if (!isRead) ...[
                    const SizedBox(width: 12),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _primaryOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isZh, bool isMs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_off_outlined,
              size: 56,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              isZh
                  ? '暂无通知'
                  : (isMs ? 'Tiada pemberitahuan' : 'No notifications'),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isZh
                  ? '有关预约、付款和消息的更新将在此显示'
                  : (isMs
                  ? 'Kemas kini tentang tempahan, pembayaran dan mesej akan dipaparkan di sini'
                  : 'Updates about bookings, payments and messages will appear here'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
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
        return _primaryOrange;
    }
  }
}