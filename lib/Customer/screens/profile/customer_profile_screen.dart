import '../../widgets/customer_refresh.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_profile_service.dart';
import '../../widgets/account_widgets.dart';
import '../../widgets/customer_dialogs.dart';
import '../../../shared/chat/chat_inbox_screen.dart';
import 'customer_edit_profile_screen.dart';
import 'customer_saved_addresses_screen.dart';
import 'customer_settings_screen.dart';
import '../booking/customer_bookings_screen.dart';
import '../review/customer_my_reviews_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  final CustomerProfileService? service;
  const CustomerProfileScreen({super.key, this.service});
  @override
  State<CustomerProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<CustomerProfileScreen> {
  late final _service = widget.service ?? CustomerProfileService();
  Map<String, dynamic>? _profile;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _service.getProfileData();
      if (mounted)
        setState(() {
          _profile = p;
          _error = null;
        });
    } catch (e) {
      if (mounted) {
        setState(() => _error = CustomerDialogs.errorMessage(e));
        await CustomerDialogs.error(context, e);
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  void _edit() => _open(
    CustomerEditProfileScreen(profileData: _profile, service: _service),
  );
  Widget _shortcut(IconData icon, String label, Widget page) => Expanded(
    child: InkWell(
      onTap: () => _open(page),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        child: Column(
          children: [
            Icon(icon, size: 28, color: CustomerTheme.primary),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final photo = _profile?['profile_photo_url']?.toString() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomerRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.zero,
          children: [
            Container(
              color: CustomerTheme.primary,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          InkWell(
                            onTap: _profile == null ? null : _edit,
                            child: Semantics(
                              button: true,
                              label: 'Edit profile photo and personal details',
                              child: CircleAvatar(
                                radius: 34,
                                backgroundColor: Colors.white,
                                backgroundImage: photo.isEmpty
                                    ? null
                                    : NetworkImage(photo),
                                child: photo.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        color: CustomerTheme.primary,
                                        size: 42,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: InkWell(
                              onTap: _profile == null ? null : _edit,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _profile?['full_name']?.toString() ??
                                        'My account',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_profile == null && _error == null)
              const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  AccountGroup(
                    children: [
                      AccountRow(
                        label: 'My services & bookings',
                        value: 'View all',
                        onTap: () => _open(const CustomerBookingsScreen()),
                      ),
                      Row(
                        children: [
                          _shortcut(
                            Icons.receipt_long_outlined,
                            'Bookings',
                            const CustomerBookingsScreen(),
                          ),
                          _shortcut(
                            Icons.rate_review_outlined,
                            'My reviews',
                            const CustomerMyReviewsScreen(),
                          ),
                          _shortcut(
                            Icons.chat_bubble_outline,
                            'Chats',
                            const ChatInboxScreen(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  AccountGroup(
                    title: 'Manage my account',
                    children: [
                      AccountRow(
                        label: 'My Addresses',
                        subtitle: 'Where your service takes place',
                        icon: Icons.location_on_outlined,
                        onTap: () =>
                            _open(const CustomerSavedAddressesScreen()),
                      ),
                      AccountRow(
                        label: 'Profile & Preferences',
                        subtitle: 'Personal details and preferred services',
                        icon: Icons.person_outline,
                        onTap: _profile == null ? null : _edit,
                      ),
                    ],
                  ),
                  AccountGroup(
                    children: [
                      AccountRow(
                        label: 'Settings & Help',
                        icon: Icons.settings_outlined,
                        onTap: () => _open(const CustomerSettingsScreen()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
