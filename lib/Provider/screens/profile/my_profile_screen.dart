import 'package:flutter/material.dart';

import 'package:fyp2/Provider/services/profile_service.dart';
import 'package:fyp2/Provider/services/auth_service.dart';
import 'package:fyp2/Provider/services/notification_service.dart';

import 'update_profile_screen.dart';
import 'certifications_screen.dart';
import 'service_areas_screen.dart';
import 'working_hours_screen.dart';

import 'package:fyp2/Provider/screens/services/my_services_screen.dart';
import 'package:fyp2/Provider/screens/bookings/my_bookings_screen.dart';
import 'package:fyp2/Provider/screens/earnings/earnings_screen.dart';
import 'package:fyp2/Provider/screens/notifications/notification_screen.dart';
import 'package:fyp2/Provider/screens/ai/ai_job_matching_screen.dart';
import 'package:fyp2/Provider/screens/ai/ai_schedule_screen.dart';
import 'package:fyp2/shared/portal_entry_screen.dart';

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
  int _tab = 0;

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
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
          content: Text('Failed to load profile: $e'),
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
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log Out'),
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildProfileTab(),
      const MyServicesScreen(),
      const MyBookingsScreen(),
      const EarningsScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      // AppBar only shows on the Profile tab
      appBar: _tab == 0
          ? AppBar(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          // ---- Notification Bell with Unread Badge ----
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _notificationService.getMyNotifications(),
            builder: (context, snapshot) {
              final unread = (snapshot.data ?? [])
                  .where((n) => n['is_read'] != true)
                  .length;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Notifications',
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pages[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _primaryOrange,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Services'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month), label: 'Bookings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.attach_money), label: 'Earnings'),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    final name = _profile?['business_name'] ?? 'My Business';
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
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Profile Header Card ----
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
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: _lightOrange,
                      backgroundImage:
                      photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                      child: photoUrl.isEmpty
                          ? Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _primaryOrange,
                        ),
                      )
                          : null,
                    ),
                    const SizedBox(width: 12),
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
                          const SizedBox(height: 2),
                          Text(
                            bio,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.orange, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '$rating · $years years',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _statusBadge(status),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout),
                      color: Colors.red.shade400,
                      onPressed: _logout,
                      tooltip: 'Log Out',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ---- Menu Tiles ----
            _tile('Update Personal Info', Icons.edit_outlined, () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const UpdateProfileScreen()),
              );
              _load();
            }),
            _tile('Certifications', Icons.workspace_premium_outlined, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CertificationsScreen()),
              );
            }),
            _tile('Service Areas', Icons.location_on_outlined, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ServiceAreasScreen()),
              );
            }),
            _tile('Working Hours', Icons.access_time_outlined, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WorkingHoursScreen()),
              );
            }),

            // ---- AI Features ----
            _tile('AI Job Matching', Icons.auto_awesome, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AiJobMatchingScreen()),
              );
            }),
            _tile('AI Smart Schedule', Icons.schedule, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AiScheduleScreen()),
              );
            }),

            const SizedBox(height: 20),

            // ---- Submit for Verification ----
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _service
                      .updateProfile({'verification_status': 'Pending'});
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Submitted for verification'),
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
                label: const Text(
                  'Submit for Verification',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
            const SizedBox(height: 20),
          ],
        ),
      ),
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
      // Pending
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
            status,
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

  Widget _tile(String label, IconData icon, VoidCallback onTap) => Card(
    elevation: 1,
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: _borderOrange),
    ),
    child: ListTile(
      leading: Icon(icon, color: _primaryOrange),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    ),
  );
}