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
import 'help_centre.dart'; // <-- Added Help Centre import

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

  // Tab index: 0 = Home, 1 = Bookings, 2 = AI Match, 3 = AI Schedule,
  //            4 = Schedule, 5 = Profile
  int _tab = 0;

  // --- Scroll-driven navigation visibility ---
  bool _navVisible = true;
  double _scrollTravel = 0;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Failed to load profile. Please try again.')),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Log Out')),
        content: Text(tr('Are you sure you want to log out?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr('Log Out')),
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
        title: Text(tr('Profile'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: tr('Chats'),
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
                    tooltip: tr('Notifications'),
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
    final name = _profile?['business_name'] ?? tr('My Business');
    final bio = _profile?['bio'] ?? 'No bio yet';
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
                                    tr('{0} · {1} years', [rating, years]),
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _lightOrange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          bio,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                            height: 1.4,
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
            _sectionLabel('ACCOUNT'),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: 'Update Personal Info',
                subtitle: 'Name, bio, phone, and profile photo',
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
                title: 'Certifications',
                subtitle: 'Upload and manage your certificates',
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
            _sectionLabel('SERVICE SETTINGS'),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: 'My Services',
                subtitle: 'Services you offer to customers',
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
                title: 'Service Areas',
                subtitle: 'Where you work and travel radius',
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
                title: 'Working Hours',
                subtitle: 'Set your weekly availability',
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
            _sectionLabel('EARNINGS & REVIEWS'),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: 'Earnings Dashboard',
                subtitle: 'View your income and payouts',
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
                title: 'My Reviews',
                subtitle: 'See what customers say about you',
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
            _sectionLabel('SUPPORT'),
            const SizedBox(height: 8),
            _menuGroup([
              _menuItem(
                title: 'Help Centre',
                subtitle: 'Contact admin and follow your requests',
                icon: Icons.support_agent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HelpCentreScreen()),
                  );
                },
              ),
              _menuItem(
                title: 'Privacy',
                subtitle: 'Review your privacy notice & data preferences',
                icon: Icons.privacy_tip_outlined,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                  );
                },
              ),
              _menuItem(
                title: 'About Local Life Service Assistant',
                subtitle: 'App overview, version and terms',
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
            _sectionLabel('SYSTEM'),
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
                              tr('Log Out'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr('Sign out of your account'),
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
                            Text(tr('Submitted for verification')),
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
                  label: Text(tr('Submit for Verification'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
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
        tr(text),
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
                    tr(title),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr(subtitle),
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
    Color bg;
    Color fg;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'verified':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        icon = Icons.verified;
        break;
      case 'rejected':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        icon = Icons.cancel;
        break;
      case 'suspended':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade700;
        icon = Icons.block;
        break;
      default:
        bg = _lightOrange;
        fg = _primaryOrange;
        icon = Icons.pending;
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
            tr(status),
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