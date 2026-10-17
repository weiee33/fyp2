import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/customer_unread_badge.dart';
import '../../widgets/customer_refresh.dart';
import '../../widgets/customer_nav_insets.dart';
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
            if (label == 'Chats' || label == 'Bookings')
              CustomerUnreadBadge(
                kind: label == 'Chats' ? 'chats' : 'bookings',
                enabled: widget.service == null,
                child: Icon(icon, size: 28, color: CustomerTheme.primary),
              )
            else
              Icon(icon, size: 28, color: CustomerTheme.primary),
            const SizedBox(height: 10),
            Text(
              tr(label),
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
    AppLanguage.watch(context);
    final photo = _profile?['profile_photo_url']?.toString() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomerRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.only(bottom: CustomerNavInsets.bottomOf(context)),
          children: [
            Container(
              color: CustomerTheme.primary,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    children: [
                      Column(
                        children: [
                          InkWell(
                            onTap: _profile == null ? null : _edit,
                            child: Semantics(
                              button: true,
                              label: tr(
                                'Edit profile photo and personal details',
                              ),
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
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _profile == null ? null : _edit,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  _profile?['full_name']?.toString() ??
                                      tr('My account'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
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
                title: Text(tr(_error!)),
                trailing: TextButton(
                  onPressed: _load,
                  child: Text(tr('Retry')),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  AccountGroup(
                    children: [
                      Row(
                        children: [
                          _shortcut(
                            Icons.receipt_long_outlined,
                            'Bookings',
                            const CustomerBookingsScreen(),
                          ),
                          _shortcut(
                            Icons.rate_review_outlined,
                            'Reviews',
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
                    title: tr('Manage my account'),
                    children: [
                      AccountRow(
                        label: tr('My Addresses'),
                        icon: Icons.location_on_outlined,
                        onTap: () =>
                            _open(const CustomerSavedAddressesScreen()),
                      ),
                      AccountRow(
                        label: tr('Profile & Preferences'),
                        icon: Icons.person_outline,
                        onTap: _profile == null ? null : _edit,
                      ),
                    ],
                  ),
                  AccountGroup(
                    children: [
                      AccountRow(
                        label: tr('Settings & Help'),
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
