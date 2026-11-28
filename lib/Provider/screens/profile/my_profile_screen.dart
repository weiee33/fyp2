import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:fyp2/shared/localization/language_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/chat/chat_inbox_screen.dart';
import 'package:fyp2/Provider/services/profile_service.dart';
import 'package:fyp2/Provider/services/auth_service.dart';
import 'package:fyp2/Provider/services/notification_service.dart';

import 'update_profile_screen.dart';
import 'certifications_screen.dart';
import 'service_areas_screen.dart';
import 'working_hours_screen.dart';
import 'privacy_screen.dart';
import 'about_app_screen.dart';
import 'help_centre.dart';
import 'package:fyp2/Customer/screens/auth/customer_forgot_password_screen.dart';


import 'package:fyp2/Provider/screens/services/my_services_screen.dart';
import 'package:fyp2/Provider/screens/bookings/my_bookings_screen.dart';
import 'package:fyp2/Provider/screens/earnings/earnings_screen.dart';
import 'package:fyp2/Provider/screens/notifications/notification_screen.dart';
import 'package:fyp2/shared/portal_entry_screen.dart';
import 'package:fyp2/Provider/screens/schedule/schedule_screen.dart';
import 'package:fyp2/Provider/screens/home/provider_home_screen.dart';
import 'package:fyp2/Provider/screens/review/review_screen.dart';

import 'package:fyp2/Provider/screens/home/provider_floating_nav_bar.dart';

import 'package:fyp2/Provider/screens/ai/ai_job_matching_screen.dart';
import 'package:fyp2/Provider/screens/ai/ai_schedule_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _service = ProfileService();
  final _auth = AuthService();
  final _notificationService = NotificationService();

  Map<String, dynamic>? _profile;
  bool _loading = true;

  // Tab index
  int _tab = 0;

  // Scroll-driven navigation visibility
  bool _navVisible = true;
  double _scrollTravel = 0;

  // Bio Expand State
  bool _isBioExpanded = false;

  // 折叠面板展开状态
  bool _accountExpanded = true;
  bool _serviceExpanded = false;
  bool _earningsExpanded = false;
  bool _supportExpanded = false;

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        MediaQuery.accessibleNavigationOf(context)) {
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;

      if (notification.metrics.pixels <=
          notification.metrics.minScrollExtent + 8) {
        _scrollTravel = 0;
        if (!_navVisible) setState(() => _navVisible = true);
      } else if (!notification.metrics.outOfRange && delta != 0) {
        if (_scrollTravel.sign != delta.sign) _scrollTravel = 0;
        _scrollTravel += delta;
        if (_scrollTravel.abs() >= 18) {
          final visible = _scrollTravel < 0;
          if (_navVisible != visible) {
            setState(() => _navVisible = visible);
          }
          _scrollTravel = 0;
        }
      }
    } else if (notification is ScrollEndNotification) {
      _scrollTravel = 0;
    }
    return false;
  }

  void _selectTab(int index) {
    setState(() {
      _tab = index;
      _navVisible = true;
      _scrollTravel = 0;
    });
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profile = await _service.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final lang = Localizations.localeOf(context).languageCode;
      _showAppDialog(
        title: lang == 'zh' ? '错误' : (lang == 'ms' ? 'Ralat' : 'Error'),
        message: lang == 'zh'
            ? '加载个人资料失败，请重试。'
            : (lang == 'ms'
            ? 'Gagal memuatkan profil. Sila cuba lagi.'
            : 'Failed to load profile. Please try again.'),
        isError: true,
      );
    }
  }

  Future<void> _logout() async {
    final lang = Localizations.localeOf(context).languageCode;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          lang == 'zh'
              ? '登出'
              : (lang == 'ms' ? 'Log Keluar' : 'Log Out'),
        ),
        content: Text(
          lang == 'zh'
              ? '您确定要登出吗？'
              : (lang == 'ms'
              ? 'Adakah anda pasti mahu log keluar?'
              : 'Are you sure you want to log out?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              lang == 'zh'
                  ? '取消'
                  : (lang == 'ms' ? 'Batal' : 'Cancel'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              lang == 'zh'
                  ? '登出'
                  : (lang == 'ms' ? 'Log Keluar' : 'Log Out'),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _auth.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PortalEntryScreen()),
          (_) => false,
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    setState(() {});
  }

  void _openChats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ChatInboxScreen(customer: false),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
      );
    }

    final lang = Localizations.localeOf(context).languageCode;

    final pages = [
      ProviderHomeScreen(onNavigateToTab: _selectTab),
      const MyBookingsScreen(),
      const AiJobMatchingScreen(),
      const AiScheduleScreen(),
      const ScheduleScreen(),
      _buildProfileTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      extendBody: true,
      appBar: _tab == 5
          ? AppBar(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          lang == 'zh'
              ? '个人资料'
              : (lang == 'ms' ? 'Profil' : 'Profile'),
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: lang == 'zh'
                ? '聊天'
                : (lang == 'ms' ? 'Sembang' : 'Chats'),
            onPressed: _openChats,
          ),
          FutureBuilder<List>(
            future: _notificationService.getMyNotifications(),
            builder: (context, snapshot) {
              final unread = (snapshot.data ?? [])
                  .where((n) => n['is_read'] != true)
                  .length;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: lang == 'zh'
                        ? '通知'
                        : (lang == 'ms'
                        ? 'Pemberitahuan'
                        : 'Notifications'),
                    onPressed: _openNotifications,
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      )
          : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: IndexedStack(
                index: _tab,
                children: pages,
              ),
            ),
          ),
          ProviderFloatingNavBar(
            currentIndex: _tab,
            onTabChanged: _selectTab,
            visible: _navVisible,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final name = _profile?['business_name'] ??
        (isZh
            ? '我的业务'
            : (isMs ? 'Perniagaan Saya' : 'My Business'));
    final bio = _profile?['bio'] ??
        (isZh
            ? '暂无简介'
            : (isMs ? 'Tiada bio lagi' : 'No bio yet'));
    final rating = _profile?['overall_rating'] ?? 0;
    final years = _profile?['years_experience'] ?? 0;
    final status = _profile?['verification_status'] ?? 'Pending';
    final photoUrl = _profile?['profile_photo_url']?.toString() ?? '';

    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'P';

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: ListView(
          // 👇 弹性物理效果
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // --- Profile Card ---
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: _lightOrange,
                          backgroundImage: photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl.isEmpty
                              ? Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: _primaryOrange,
                            ),
                          )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.orange, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    isZh
                                        ? '$rating · $years 年经验'
                                        : (isMs
                                        ? '$rating · $years tahun pengalaman'
                                        : '$rating · $years years experience'),
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _statusBadge(status),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (bio.isNotEmpty && bio != 'No bio yet') ...[
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isBioExpanded = !_isBioExpanded;
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _lightOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bio,
                                maxLines: _isBioExpanded ? null : 2,
                                overflow: _isBioExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    _isBioExpanded
                                        ? (isZh
                                        ? '收起'
                                        : (isMs
                                        ? 'Tutup'
                                        : 'See less'))
                                        : (isZh
                                        ? '查看更多'
                                        : (isMs
                                        ? 'Lihat lagi'
                                        : 'See more')),
                                    style: const TextStyle(
                                      color: _primaryOrange,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Icon(
                                    _isBioExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: _primaryOrange,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- Account Settings ---
            _buildExpandableGroup(
              title: isZh ? '账户' : (isMs ? 'AKAUN' : 'ACCOUNT'),
              isExpanded: _accountExpanded,
              onToggle: () => setState(() => _accountExpanded = !_accountExpanded),
              children: [
                _menuItem(
                  title: isZh ? '更新个人信息' : (isMs ? 'Kemas Kini Maklumat Peribadi' : 'Update Personal Info'),
                  icon: Icons.edit_outlined,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UpdateProfileScreen()),
                    );
                    _load();
                  },
                ),
                _menuItem(
                  title: isZh ? '修改密码' : (isMs ? 'Tukar Kata Laluan' : 'Change Password'),
                  icon: Icons.lock_outline,
                  onTap: () {
                    // 1. 获取当前登录账号的邮箱
                    final currentEmail = Supabase.instance.client.auth.currentUser?.email ?? '';

                    // 2. 跳转到修改密码页面，开启 requireCurrentPassword 模式
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CustomerForgotPasswordScreen(
                          initialEmail: currentEmail,
                          requireCurrentPassword: true,
                        ),
                      ),
                    );
                  },
                ),
                _languageItem(),
                _menuItem(
                  title: isZh ? '证书' : (isMs ? 'Sijil' : 'Certifications'),
                  icon: Icons.workspace_premium_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CertificationsScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- Service Settings ---
            _buildExpandableGroup(
              title: isZh ? '服务设置' : (isMs ? 'TETAPAN PERKHIDMATAN' : 'SERVICE SETTINGS'),
              isExpanded: _serviceExpanded,
              onToggle: () => setState(() => _serviceExpanded = !_serviceExpanded),
              children: [
                _menuItem(
                  title: isZh ? '我的服务' : (isMs ? 'Perkhidmatan Saya' : 'My Services'),
                  icon: Icons.work_outline,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MyServicesScreen()),
                    );
                  },
                ),
                _menuItem(
                  title: isZh ? '服务区域' : (isMs ? 'Kawasan Perkhidmatan' : 'Service Areas'),
                  icon: Icons.location_on_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ServiceAreasScreen()),
                    );
                  },
                ),
                _menuItem(
                  title: isZh ? '工作时间' : (isMs ? 'Waktu Bekerja' : 'Working Hours'),
                  icon: Icons.access_time_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WorkingHoursScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- Earnings & Reviews ---
            _buildExpandableGroup(
              title: isZh ? '收益与评价' : (isMs ? 'PENDAPATAN & ULASAN' : 'EARNINGS & REVIEWS'),
              isExpanded: _earningsExpanded,
              onToggle: () => setState(() => _earningsExpanded = !_earningsExpanded),
              children: [
                _menuItem(
                  title: isZh ? '收益面板' : (isMs ? 'Papan Pemuka Pendapatan' : 'Earnings Dashboard'),
                  icon: Icons.attach_money,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EarningsScreen()),
                    );
                  },
                ),
                _menuItem(
                  title: isZh ? '我的评价' : (isMs ? 'Ulasan Saya' : 'My Reviews'),
                  icon: Icons.star_outline,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReviewsScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- Support & Legal ---
            _buildExpandableGroup(
              title: isZh ? '支持' : (isMs ? 'SOKONGAN' : 'SUPPORT'),
              isExpanded: _supportExpanded,
              onToggle: () => setState(() => _supportExpanded = !_supportExpanded),
              children: [
                _menuItem(
                  title: isZh ? '帮助中心' : (isMs ? 'Pusat Bantuan' : 'Help Centre'),
                  icon: Icons.support_agent,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HelpCentreScreen()),
                    );
                  },
                ),
                _menuItem(
                  title: isZh ? '隐私' : (isMs ? 'Privasi' : 'Privacy'),
                  icon: Icons.privacy_tip_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                    );
                  },
                ),
                _menuItem(
                  title: isZh ? '关于本地生活服务助手' : (isMs ? 'Mengenai Pembantu Perkhidmatan Kehidupan Tempatan' : 'About Local Life Service Assistant'),
                  icon: Icons.info_outline,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutAppScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- System (直接显示，不折叠) ---
            _menuGroup([
              InkWell(
                onTap: _logout,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.logout, color: Colors.red.shade600, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isZh ? '登出' : (isMs ? 'Log Keluar' : 'Log Out'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                    ],
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // --- Verification Button ---
            if (status.toLowerCase() != 'verified')
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _service.updateProfile({'verification_status': 'Pending'});
                    if (!mounted) return;
                    _showAppDialog(
                      title: isZh ? '成功' : (isMs ? 'Berjaya' : 'Success'),
                      message: isZh
                          ? '已提交验证'
                          : (isMs
                          ? 'Dihantar untuk pengesahan'
                          : 'Submitted for verification'),
                      isError: false,
                    );
                    _load();
                  },
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(
                    isZh ? '提交验证' : (isMs ? 'Hantar untuk Pengesahan' : 'Submit for Verification'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // 自定义手风琴折叠控件
  Widget _buildExpandableGroup({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            ...children,
          ],
        ],
      ),
    );
  }

  Widget _menuGroup(List<Widget> items) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              Divider(
                height: 1,
                indent: 56,
                endIndent: 12,
                color: Colors.grey.shade200,
              ),
          ],
        ],
      ),
    );
  }

  Widget _menuItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _lightOrange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _primaryOrange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _languageItem() {
    return Builder(
      builder: (context) {
        final lang = Localizations.localeOf(context).languageCode;
        final isZh = lang == 'zh';
        final isMs = lang == 'ms';

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LanguageScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _lightOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.language_outlined,
                      color: _primaryOrange, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isZh ? '应用语言' : (isMs ? 'Bahasa Aplikasi' : 'App Language'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    final lang = Localizations.localeOf(context).languageCode;

    Color bg;
    Color fg;
    IconData icon;
    String displayStatus;

    switch (status.toLowerCase()) {
      case 'verified':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        icon = Icons.verified;
        displayStatus = lang == 'zh'
            ? '已验证'
            : (lang == 'ms' ? 'DISAHKAN' : 'VERIFIED');
        break;
      case 'rejected':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        icon = Icons.cancel;
        displayStatus = lang == 'zh'
            ? '已拒绝'
            : (lang == 'ms' ? 'DITOLAK' : 'REJECTED');
        break;
      case 'suspended':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade700;
        icon = Icons.block;
        displayStatus = lang == 'zh'
            ? '已暂停'
            : (lang == 'ms' ? 'DIGANTUNG' : 'SUSPENDED');
        break;
      default:
        bg = _lightOrange;
        fg = _primaryOrange;
        icon = Icons.pending;
        displayStatus = lang == 'zh'
            ? '待处理'
            : (lang == 'ms' ? 'TERTUNDA' : 'PENDING');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            displayStatus,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}