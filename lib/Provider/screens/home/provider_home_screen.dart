import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fyp2/shared/chat/chat_inbox_screen.dart';
import 'package:fyp2/Provider/screens/notifications/notification_screen.dart';
import 'package:fyp2/Provider/services/notification_service.dart';
import 'package:fyp2/Provider/screens/earnings/earnings_screen.dart';
import 'package:fyp2/Provider/screens/profile/service_areas_screen.dart';

class ProviderHomeScreen extends StatefulWidget {
  // 接收一个回调，用于切换底部导航的 Tab
  final Function(int) onNavigateToTab;

  const ProviderHomeScreen({super.key, required this.onNavigateToTab});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> {
  final _client = Supabase.instance.client;
  final _notificationService = NotificationService();

  bool _loading = true;
  String? _error;

  // 数据状态
  Map<String, dynamic>? _profile;
  double _todayEarnings = 0.0;
  int _pendingCount = 0;
  int _activeCount = 0;
  int _completedThisWeek = 0;
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

      // 1. 获取 Provider Profile 和 Provider ID
      final profileRow = await _client
          .from('provider_profiles')
          .select()
          .eq('user_id', uid)
          .maybeSingle();

      if (profileRow == null) throw Exception('Provider profile not found');
      _profile = profileRow;
      final providerId = profileRow['provider_id'].toString();

      // 2. 获取今日收入 (从 provider_earnings 表)
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();
      final earningsRes = await _client
          .from('provider_earnings')
          .select('net_earnings')
          .eq('provider_id', providerId)
          .gte('created_at', startOfDay);

      _todayEarnings = (earningsRes as List).fold(0.0, (sum, row) => sum + ((row['net_earnings'] as num?)?.toDouble() ?? 0.0));

      // 3. 获取各项预约数量
      final bookingsRes = await _client
          .from('bookings')
          .select('booking_id, booking_status, scheduled_datetime, service_name_snapshot, total_amount')
          .eq('provider_id', providerId)
          .neq('booking_status', 'Cancelled')
          .order('scheduled_datetime', ascending: true);

      final bookings = List<Map<String, dynamic>>.from(bookingsRes);

      _pendingCount = bookings.where((b) => b['booking_status'] == 'Pending').length;
      _activeCount = bookings.where((b) => b['booking_status'] == 'In-Progress').length;

      // 计算本周完成数量
      _completedThisWeek = bookings.where((b) {
        if (b['booking_status'] != 'Completed') return false;
        return true;
      }).length;

      // 4. 获取最近的 3 个 Pending 预约
      _recentPending = bookings
          .where((b) => b['booking_status'] == 'Pending')
          .take(3)
          .toList();

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

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    if (mounted) setState(() {});
  }

  void _openChats() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatInboxScreen(customer: false)));
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: _primaryOrange)));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(tr('Please check your connection and try again.'), style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadData,
                style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
                child: Text(tr('Retry'), style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    }

    final name = _profile?['business_name'] ?? tr('Provider');
    final region = _profile?['region'] ?? tr('Your Area');
    final radius = _profile?['service_radius_km'] ?? 10;

    return Scaffold(
      backgroundColor: _bgColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: _primaryOrange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ==================== Top Header (Orange) ====================
              Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
                decoration: const BoxDecoration(
                  color: _primaryOrange,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Greeting + Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Good day,'),
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
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
                            _iconBtn(Icons.chat_bubble_outline, _openChats),
                            const SizedBox(width: 8),
                            // Notification with Badge
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _notificationService.getMyNotifications(),
                              builder: (context, snapshot) {
                                final unread = (snapshot.data ?? []).where((n) => n['is_read'] != true).length;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _iconBtn(Icons.notifications_outlined, _openNotifications),
                                    if (unread > 0)
                                      Positioned(
                                        right: 4,
                                        top: 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                          child: Text(
                                            unread > 9 ? '9+' : '$unread',
                                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
                    const SizedBox(height: 20),

                    // Row 2: Location
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ServiceAreasScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr('{0} · {1} km radius', [region, radius]),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Today's Earnings Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Today\'s Earnings'),
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'RM ${_todayEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const Icon(Icons.account_balance_wallet_outlined, color: _primaryOrange, size: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ==================== Dashboard Cards ====================
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Row
                    Row(
                      children: [
                        _statCard('Pending', _pendingCount, Colors.orange),
                        const SizedBox(width: 10),
                        _statCard('Active', _activeCount, Colors.blue),
                        const SizedBox(width: 10),
                        _statCard('Done (Wk)', _completedThisWeek, Colors.green),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Quick Actions
                    Text(tr('Quick Actions'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _quickActionBtn(Icons.book, 'Bookings', () => widget.onNavigateToTab(1)),
                        const SizedBox(width: 10),
                        _quickActionBtn(Icons.attach_money, 'Earnings', () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsScreen()));
                        }),
                        const SizedBox(width: 10),
                        _quickActionBtn(Icons.schedule, 'Schedule', () => widget.onNavigateToTab(2)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Recent Pending Bookings
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tr('Pending Requests'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                        TextButton(
                          onPressed: () => widget.onNavigateToTab(1),
                          child: Text(tr('View all'), style: TextStyle(color: _primaryOrange, fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_recentPending.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(tr('No pending requests'), style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    else
                      ..._recentPending.map((b) => _pendingCard(b)),

                    const SizedBox(height: 100), // 底部留白，防止被悬浮导航遮挡
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _statCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(tr(label),
              style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionBtn(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
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
              Text(tr(label), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
            ],
          ),
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
        timeStr = '${dt.day}/${dt.month} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
          decoration: BoxDecoration(color: _lightOrange, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.pending_actions, color: _primaryOrange),
        ),
        title: Text(serviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(timeStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Text('RM $amount', style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryOrange)),
        onTap: () => widget.onNavigateToTab(1), // 跳到 Bookings 去处理
      ),
    );
  }
}
