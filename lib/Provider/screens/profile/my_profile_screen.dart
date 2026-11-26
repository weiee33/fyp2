import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:fyp2/shared/localization/language_screen.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang == 'zh'
                ? '加载个人资料失败，请重试。'
                : (lang == 'ms'
                ? 'Gagal memuatkan profil. Sila cuba lagi.'
                : 'Failed to load profile. Please try again.'),
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
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
          style: const TextStyle(fontWeight: FontWeight.w600),
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
    final name = _profile?['business_name'] ??
        (lang == 'zh'
            ? '我的业务'
            : (lang == 'ms' ? 'Perniagaan Saya' : 'My Business'));
    final bio = _profile?['bio'] ??
        (lang == 'zh'
            ? '暂无简介'
            : (lang == 'ms' ? 'Tiada bio lagi' : 'No bio yet'));
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
                                    lang == 'zh'
                                        ? '$rating · $years 年经验'
                                        : (lang == 'ms'
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
                                        ? (lang == 'zh'
                                        ? '收起'
                                        : (lang == 'ms'
                                        ? 'Tutup'
                                        : 'See less'))
                                        : (lang == 'zh'
                                        ? '查看更多'
                                        : (lang == 'ms'
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
            _sectionLabel(
              lang == 'zh'
                  ? '账户'
                  : (lang == 'ms' ? 'AKAUN' : 'ACCOUNT'),
            ),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: lang == 'zh'
                    ? '更新个人信息'
                    : (lang == 'ms'
                    ? 'Kemas Kini Maklumat Peribadi'
                    : 'Update Personal Info'),
                subtitle: lang == 'zh'
                    ? '姓名、简介、电话和头像'
                    : (lang == 'ms'
                    ? 'Nama, bio, telefon dan foto profil'
                    : 'Name, bio, phone, and profile photo'),
                icon: Icons.edit_outlined,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UpdateProfileScreen()),
                  );
                  _load();
                },
              ),
              _languageItem(),
              _menuItem(
                title: lang == 'zh'
                    ? '证书'
                    : (lang == 'ms' ? 'Sijil' : 'Certifications'),
                subtitle: lang == 'zh'
                    ? '上传和管理您的证书'
                    : (lang == 'ms'
                    ? 'Muat naik dan urus sijil anda'
                    : 'Upload and manage your certificates'),
                icon: Icons.workspace_premium_outlined,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CertificationsScreen()),
                  );
                },
              ),
            ]),
            const SizedBox(height: 20),

            // --- Service Settings ---
            _sectionLabel(
              lang == 'zh'
                  ? '服务设置'
                  : (lang == 'ms' ? 'TETAPAN PERKHIDMATAN' : 'SERVICE SETTINGS'),
            ),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: lang == 'zh'
                    ? '我的服务'
                    : (lang == 'ms' ? 'Perkhidmatan Saya' : 'My Services'),
                subtitle: lang == 'zh'
                    ? '您向客户提供的服务'
                    : (lang == 'ms'
                    ? 'Perkhidmatan yang anda tawarkan'
                    : 'Services you offer to customers'),
                icon: Icons.work_outline,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MyServicesScreen()),
                  );
                },
              ),
              _menuItem(
                title: lang == 'zh'
                    ? '服务区域'
                    : (lang == 'ms' ? 'Kawasan Perkhidmatan' : 'Service Areas'),
                subtitle: lang == 'zh'
                    ? '您的工作地点和出行半径'
                    : (lang == 'ms'
                    ? 'Di mana anda bekerja dan radius perjalanan'
                    : 'Where you work and travel radius'),
                icon: Icons.location_on_outlined,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ServiceAreasScreen()),
                  );
                },
              ),
              _menuItem(
                title: lang == 'zh'
                    ? '工作时间'
                    : (lang == 'ms' ? 'Waktu Bekerja' : 'Working Hours'),
                subtitle: lang == 'zh'
                    ? '设置您的每周可用时间'
                    : (lang == 'ms'
                    ? 'Tetapkan ketersediaan mingguan anda'
                    : 'Set your weekly availability'),
                icon: Icons.access_time_outlined,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WorkingHoursScreen()),
                  );
                },
              ),
            ]),
            const SizedBox(height: 20),

            // --- Earnings & Reviews ---
            _sectionLabel(
              lang == 'zh'
                  ? '收益与评价'
                  : (lang == 'ms'
                  ? 'PENDAPATAN & ULASAN'
                  : 'EARNINGS & REVIEWS'),
            ),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: lang == 'zh'
                    ? '收益面板'
                    : (lang == 'ms'
                    ? 'Papan Pemuka Pendapatan'
                    : 'Earnings Dashboard'),
                subtitle: lang == 'zh'
                    ? '查看您的收入和付款'
                    : (lang == 'ms'
                    ? 'Lihat pendapatan dan pembayaran anda'
                    : 'View your income and payouts'),
                icon: Icons.attach_money,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EarningsScreen()),
                  );
                },
              ),
              _menuItem(
                title: lang == 'zh'
                    ? '我的评价'
                    : (lang == 'ms' ? 'Ulasan Saya' : 'My Reviews'),
                subtitle: lang == 'zh'
                    ? '查看客户对您的评价'
                    : (lang == 'ms'
                    ? 'Lihat apa yang pelanggan katakan tentang anda'
                    : 'See what customers say about you'),
                icon: Icons.star_outline,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ReviewsScreen()),
                  );
                },
              ),
            ]),
            const SizedBox(height: 20),

            // --- Support & Legal ---
            _sectionLabel(
              lang == 'zh'
                  ? '支持'
                  : (lang == 'ms' ? 'SOKONGAN' : 'SUPPORT'),
            ),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: lang == 'zh'
                    ? '帮助中心'
                    : (lang == 'ms' ? 'Pusat Bantuan' : 'Help Centre'),
                subtitle: lang == 'zh'
                    ? '联系管理员并跟踪您的请求'
                    : (lang == 'ms'
                    ? 'Hubungi admin dan ikuti permintaan anda'
                    : 'Contact admin and follow your requests'),
                icon: Icons.support_agent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HelpCentreScreen()),
                  );
                },
              ),
              _menuItem(
                title: lang == 'zh'
                    ? '隐私'
                    : (lang == 'ms' ? 'Privasi' : 'Privacy'),
                subtitle: lang == 'zh'
                    ? '查看您的隐私声明和数据偏好'
                    : (lang == 'ms'
                    ? 'Semak notis privasi & keutamaan data anda'
                    : 'Review your privacy notice & data preferences'),
                icon: Icons.privacy_tip_outlined,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                  );
                },
              ),
              _menuItem(
                title: lang == 'zh'
                    ? '关于本地生活服务助手'
                    : (lang == 'ms'
                    ? 'Mengenai Pembantu Perkhidmatan Kehidupan Tempatan'
                    : 'About Local Life Service Assistant'),
                subtitle: lang == 'zh'
                    ? '应用概述、版本和条款'
                    : (lang == 'ms'
                    ? 'Gambaran keseluruhan apl, versi dan terma'
                    : 'App overview, version and terms'),
                icon: Icons.info_outline,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutAppScreen()),
                  );
                },
              ),
            ]),
            const SizedBox(height: 20),

            // --- System ---
            _sectionLabel(
              lang == 'zh'
                  ? '系统'
                  : (lang == 'ms' ? 'SISTEM' : 'SYSTEM'),
            ),
            const SizedBox(height: 8),
            _menuGroup([
              InkWell(
                onTap: _logout,
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.logout,
                            color: Colors.red.shade600, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang == 'zh'
                                  ? '登出'
                                  : (lang == 'ms' ? 'Log Keluar' : 'Log Out'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              lang == 'zh'
                                  ? '退出您的账户'
                                  : (lang == 'ms'
                                  ? 'Log keluar dari akaun anda'
                                  : 'Sign out of your account'),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: Colors.grey.shade400, size: 20),
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
                    await _service
                        .updateProfile({'verification_status': 'Pending'});
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              lang == 'zh'
                                  ? '已提交验证'
                                  : (lang == 'ms'
                                  ? 'Dihantar untuk pengesahan'
                                  : 'Submitted for verification'),
                            ),
                          ],
                        ),
                        backgroundColor: Colors.green.shade600,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                    _load();
                  },
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(
                    lang == 'zh'
                        ? '提交验证'
                        : (lang == 'ms'
                        ? 'Hantar untuk Pengesahan'
                        : 'Submit for Verification'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey.shade600,
        ),
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
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isZh
                            ? '应用语言'
                            : (isMs ? 'Bahasa Aplikasi' : 'App Language'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isZh
                            ? '更改应用语言'
                            : (isMs
                            ? 'Tukar bahasa aplikasi'
                            : 'Change app language'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.grey.shade400, size: 20),
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