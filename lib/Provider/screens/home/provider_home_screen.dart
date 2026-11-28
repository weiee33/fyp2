import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fyp2/shared/chat/chat_inbox_screen.dart';
import 'package:fyp2/shared/chat/chat_service.dart'; // 👈 引入了你的 ChatService
import 'package:fyp2/Provider/screens/notifications/notification_screen.dart';
import 'package:fyp2/Provider/services/notification_service.dart';
import 'package:fyp2/Provider/screens/earnings/earnings_screen.dart';
import 'package:fyp2/Provider/screens/profile/service_areas_screen.dart';

import 'package:fyp2/Provider/screens/services/my_services_screen.dart';
import 'package:fyp2/Provider/screens/profile/working_hours_screen.dart';
import 'package:fyp2/Provider/screens/review/review_screen.dart';

class ProviderHomeScreen extends StatefulWidget {
  final Function(int) onNavigateToTab;

  const ProviderHomeScreen({super.key, required this.onNavigateToTab});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> {
  final _client = Supabase.instance.client;
  final _notificationService = NotificationService();
  final _chatService = ChatService(); // 👈 实例化 ChatService

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _profile;
  double _weekEarnings = 0.0;
  int _pendingCount = 0;
  int _todoTodayCount = 0;
  int _completedToday = 0;
  List<Map<String, dynamic>> _recentPending = [];

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);
  static const _bgColor = Color(0xFFF5F7FA);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');

      final profileRow = await _client
          .from('provider_profiles')
          .select()
          .eq('user_id', uid)
          .maybeSingle();

      if (profileRow == null) throw Exception('Provider profile not found');
      _profile = profileRow;
      final providerId = profileRow['provider_id'].toString();

      final today = DateTime.now();
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final startOfWeekStr = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day).toUtc().toIso8601String();

      final earningsRes = await _client
          .from('provider_earnings')
          .select('net_earnings, created_at')
          .eq('provider_id', providerId)
          .gte('created_at', startOfWeekStr);

      final earningsList = List<Map<String, dynamic>>.from(earningsRes);
      _weekEarnings = earningsList.fold(
          0.0, (sum, row) => sum + ((row['net_earnings'] as num?)?.toDouble() ?? 0.0));

      final bookingsRes = await _client
          .from('bookings')
          .select('booking_id, booking_status, scheduled_datetime, service_name_snapshot, total_amount, created_at')
          .eq('provider_id', providerId)
          .neq('booking_status', 'Cancelled')
          .order('scheduled_datetime', ascending: true);

      final bookings = List<Map<String, dynamic>>.from(bookingsRes);
      final todayStartLocal = DateTime(today.year, today.month, today.day);

      final validPending = bookings.where((b) {
        if (b['booking_status'] != 'Pending') return false;
        final scheduledAt = b['scheduled_datetime']?.toString();
        if (scheduledAt == null) return true;
        final dt = DateTime.tryParse(scheduledAt)?.toLocal();
        if (dt == null) return true;
        return dt.isAfter(todayStartLocal) || dt.isAtSameMomentAs(todayStartLocal);
      }).toList();

      _pendingCount = validPending.length;
      _recentPending = validPending.take(3).toList();

      _todoTodayCount = bookings.where((b) {
        if (b['booking_status'] != 'Confirmed' && b['booking_status'] != 'In-Progress') return false;
        final dateStr = b['scheduled_datetime']?.toString();
        if (dateStr == null) return false;
        final dt = DateTime.tryParse(dateStr)?.toLocal();
        if (dt == null) return false;
        return dt.year == today.year && dt.month == today.month && dt.day == today.day;
      }).length;

      _completedToday = bookings.where((b) {
        if (b['booking_status'] != 'Completed') return false;
        final dateStr = b['scheduled_datetime']?.toString();
        if (dateStr == null) return false;
        final dt = DateTime.tryParse(dateStr)?.toLocal();
        if (dt == null) return false;
        return dt.year == today.year && dt.month == today.month && dt.day == today.day;
      }).length;

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  // 👈 新增：获取真实的聊天未读数总和
  Future<int> _getTotalUnreadChats() async {
    try {
      final inboxList = await _chatService.inbox();
      int totalUnread = 0;
      for (var chat in inboxList) {
        // 注意：这里假设你的数据中未读数字段名叫 'unread_count'
        // 如果在你的 Supabase RPC 里叫别的名字（比如 'unread' 或 'total_unread'），请替换这里！
        totalUnread += (chat['unread_count'] as num? ?? 0).toInt();
      }
      return totalUnread;
    } catch (e) {
      return 0; // 出错时返回 0
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    if (mounted) setState(() {});
  }

  void _openChats() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => const ChatInboxScreen(customer: false)));
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _primaryOrange));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final lang = Localizations.localeOf(context).languageCode;
              return Text(
                lang == 'zh'
                    ? '请检查您的网络连接并重试。'
                    : (lang == 'ms'
                    ? 'Sila semak sambungan anda dan cuba lagi.'
                    : 'Please check your connection and try again.'),
                style: const TextStyle(color: Colors.grey),
              );
            }),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
              child: Builder(builder: (context) {
                final lang = Localizations.localeOf(context).languageCode;
                return Text(
                  lang == 'zh'
                      ? '重试'
                      : (lang == 'ms' ? 'Cuba lagi' : 'Retry'),
                  style: const TextStyle(color: Colors.white),
                );
              }),
            )
          ],
        ),
      );
    }

    final name = _profile?['business_name'] ?? 'Provider';
    final region = _profile?['region'] ?? 'Area';
    final radius = _profile?['service_radius_km'] ?? 10;

    return Container(
      color: _bgColor,
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: _primaryOrange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          child: Column(
            children: [
              // Top Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
                decoration: const BoxDecoration(
                  color: _primaryOrange,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Builder(builder: (context) {
                              final lang = Localizations.localeOf(context).languageCode;
                              return Text(
                                lang == 'zh'
                                    ? '你好,'
                                    : (lang == 'ms' ? 'Selamat kembali,' : 'Good day,'),
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              );
                            }),
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            // ===== Chat 图标 =====
                            FutureBuilder<int>(
                              future: _getTotalUnreadChats(),
                              builder: (context, snapshot) {
                                final unreadChat = snapshot.data ?? 0;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 24),
                                      onPressed: _openChats,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    if (unreadChat > 0)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: const BoxDecoration(
                                              color: Colors.red, shape: BoxShape.circle),
                                          constraints: const BoxConstraints(
                                              minWidth: 16, minHeight: 16),
                                          child: Text(
                                            unreadChat > 99 ? '99+' : '$unreadChat',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: 16),

                            // ===== Notification 图标 =====
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _notificationService.getMyNotifications(),
                              builder: (context, snapshot) {
                                final unread = (snapshot.data ?? [])
                                    .where((n) => n['is_read'] != true)
                                    .length;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                                      onPressed: _openNotifications,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    if (unread > 0)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: const BoxDecoration(
                                              color: Colors.red, shape: BoxShape.circle),
                                          constraints: const BoxConstraints(
                                              minWidth: 16, minHeight: 16),
                                          child: Text(
                                            unread > 99 ? '99+' : '$unread',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ServiceAreasScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$region · $radius km',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Builder(builder: (context) {
                                final lang = Localizations.localeOf(context).languageCode;
                                return Text(
                                  lang == 'zh' ? '总余额' : (lang == 'ms' ? 'Jumlah Baki' : 'Total Balance'),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              }),
                              const Icon(Icons.account_balance_wallet_outlined, color: _primaryOrange, size: 24),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'RM ${_weekEarnings.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statCard('Pending', _pendingCount, Colors.orange),
                        const SizedBox(width: 10),
                        _statCard('To Do (Today)', _todoTodayCount, Colors.blue),
                        const SizedBox(width: 10),
                        _statCard('Done (Today)', _completedToday, Colors.green),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Builder(builder: (context) {
                      final lang = Localizations.localeOf(context).languageCode;
                      return Text(
                        lang == 'zh'
                            ? '快捷操作'
                            : (lang == 'ms' ? 'Tindakan Pantas' : 'Quick Actions'),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      );
                    }),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _quickActionBtn(
                              Icons.book, 'Bookings', () => widget.onNavigateToTab(1)),
                          const SizedBox(width: 10),
                          _quickActionBtn(Icons.attach_money, 'Earnings', () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const EarningsScreen()));
                          }),
                          const SizedBox(width: 10),
                          _quickActionBtn(Icons.work_outline, 'My Services', () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const MyServicesScreen()));
                          }),
                          const SizedBox(width: 10),
                          _quickActionBtn(Icons.access_time_outlined, 'Working Hours', () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const WorkingHoursScreen()));
                          }),
                          const SizedBox(width: 10),
                          _quickActionBtn(Icons.star_outline, 'Reviews', () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ReviewsScreen()));
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Builder(builder: (context) {
                          final lang = Localizations.localeOf(context).languageCode;
                          return Text(
                            lang == 'zh'
                                ? '待处理请求'
                                : (lang == 'ms'
                                ? 'Permintaan Tertunda'
                                : 'Pending Requests'),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          );
                        }),
                        TextButton(
                          onPressed: () => widget.onNavigateToTab(1),
                          child: Builder(builder: (context) {
                            final lang = Localizations.localeOf(context).languageCode;
                            return Text(
                              lang == 'zh'
                                  ? '查看全部'
                                  : (lang == 'ms' ? 'Lihat semua' : 'View all'),
                              style: const TextStyle(
                                  color: _primaryOrange, fontSize: 13),
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_recentPending.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _borderOrange)),
                        child: Column(
                          children: [
                            const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              final lang = Localizations.localeOf(context).languageCode;
                              return Text(
                                lang == 'zh'
                                    ? '暂无待处理请求'
                                    : (lang == 'ms'
                                    ? 'Tiada permintaan tertunda'
                                    : 'No pending requests'),
                                style: const TextStyle(color: Colors.grey),
                              );
                            }),
                          ],
                        ),
                      )
                    else
                      ..._recentPending.map((b) => _pendingCard(b)),

                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderOrange),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Builder(builder: (context) {
              final lang = Localizations.localeOf(context).languageCode;
              String displayLabel = label;
              if (lang == 'zh') {
                if (label == 'Pending') displayLabel = '待处理';
                if (label == 'To Do (Today)') displayLabel = '今日待办';
                if (label == 'Done (Today)') displayLabel = '今日完成';
              } else if (lang == 'ms') {
                if (label == 'Pending') displayLabel = 'Tertunda';
                if (label == 'To Do (Today)') displayLabel = 'Tugasan (Hari ini)';
                if (label == 'Done (Today)') displayLabel = 'Selesai (Hari ini)';
              }
              return Text(
                displayLabel,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _quickActionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderOrange),
        ),
        child: Column(
          children: [
            Icon(icon, color: _primaryOrange, size: 24),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final lang = Localizations.localeOf(context).languageCode;
              String displayLabel = label;
              if (lang == 'zh') {
                if (label == 'Bookings') displayLabel = '预约';
                if (label == 'Earnings') displayLabel = '收益';
                if (label == 'Schedule') displayLabel = '日程';
                if (label == 'My Services') displayLabel = '我的服务';
                if (label == 'Working Hours') displayLabel = '工作时间';
                if (label == 'Reviews') displayLabel = '评价';
              } else if (lang == 'ms') {
                if (label == 'Bookings') displayLabel = 'Tempahan';
                if (label == 'Earnings') displayLabel = 'Pendapatan';
                if (label == 'Schedule') displayLabel = 'Jadual';
                if (label == 'My Services') displayLabel = 'Perkhidmatan Saya';
                if (label == 'Working Hours') displayLabel = 'Waktu Bekerja';
                if (label == 'Reviews') displayLabel = 'Ulasan';
              }
              return Text(
                displayLabel,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> b) {
    final serviceName = b['service_name_snapshot'] ?? 'Service';
    final amount = (b['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final scheduledAt = b['scheduled_datetime']?.toString();

    String timeStr = 'TBD';
    if (scheduledAt != null) {
      final dt = DateTime.tryParse(scheduledAt)?.toLocal();
      if (dt != null) {
        timeStr =
        '${dt.day}/${dt.month} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return Card(
      elevation: 1,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: _lightOrange, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.pending_actions, color: _primaryOrange),
        ),
        title: Text(serviceName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(timeStr,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Text('RM $amount',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: _primaryOrange)),
        onTap: () => widget.onNavigateToTab(1),
      ),
    );
  }
}