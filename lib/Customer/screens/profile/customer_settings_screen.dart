import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/account_widgets.dart';
import '../../widgets/customer_dialogs.dart';
import '../../services/customer_profile_service.dart';
import '../../../shared/portal_entry_screen.dart';
import '../../../shared/chat/chat_inbox_screen.dart';
import '../auth/customer_forgot_password_screen.dart';
import 'customer_edit_profile_screen.dart';
import 'customer_saved_addresses_screen.dart';

Future<void> customerSignOut(
  BuildContext context, {
  bool allDevices = false,
}) async {
  if (!await CustomerDialogs.confirm(
    context,
    title: allDevices ? 'Sign out all devices?' : 'Log out?',
    message: allDevices
        ? 'This ends your refresh sessions on every device. Existing access can remain valid until its current token expires.'
        : 'You can sign in again with your email and password.',
  ))
    return;
  try {
    await Supabase.instance.client.auth.signOut(
      scope: allDevices ? SignOutScope.global : SignOutScope.local,
    );
    if (!context.mounted) return;
    await CustomerDialogs.show(
      context,
      title: 'Signed out',
      message: allDevices
          ? 'Your refresh sessions have been ended.'
          : 'You have signed out successfully.',
    );
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PortalEntryScreen()),
      (_) => false,
    );
  } catch (e) {
    if (context.mounted) await CustomerDialogs.error(context, e);
  }
}

class CustomerSettingsScreen extends StatelessWidget {
  const CustomerSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      title: const Text('Account Settings'),
      actions: [
        IconButton(
          tooltip: 'Chats',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatInboxScreen()),
          ),
          icon: const Icon(Icons.chat_bubble_outline),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(10),
      children: [
        AccountGroup(
          title: 'My account',
          children: [
            AccountRow(
              label: 'Account & Security',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CustomerAccountSecurityScreen(),
                ),
              ),
            ),
            AccountRow(
              label: 'My Addresses',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CustomerSavedAddressesScreen(),
                ),
              ),
            ),
          ],
        ),
        AccountGroup(
          title: 'Communication',
          children: [
            AccountRow(
              label: 'Chats',
              subtitle: 'Search, pin, delete or block a conversation',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatInboxScreen()),
              ),
            ),
          ],
        ),
        AccountGroup(
          title: 'Support',
          children: [
            AccountRow(
              label: 'Help Centre',
              onTap: () => CustomerDialogs.show(
                context,
                title: 'Booking help',
                message:
                    '1. Choose a service and address.\n2. Discuss your preferred time using Chat.\n3. Submit the booking and wait for the provider to accept.\n4. Pay from the accepted booking.\n5. Track progress, then review the completed service.\n\nChat agreements do not reserve a time slot. Always use the booking screen.',
              ),
            ),
            AccountRow(
              label: 'Privacy',
              onTap: () => CustomerDialogs.show(
                context,
                title: 'Your information',
                message:
                    'Providers receive the details needed for your bookings and the messages you send them. Your optional birthday and gender are not part of the provider profile view. Deleting a chat clears your visible history; it does not delete the other person’s copy.',
              ),
            ),
            AccountRow(
              label: 'About Local Life',
              onTap: () => CustomerDialogs.show(
                context,
                title: 'Local Life',
                message:
                    'Local Life Service Assistant\nHousehold services, bookings and provider communication.\n\nFYP mobile application.',
              ),
            ),
          ],
        ),
        OutlinedButton(
          onPressed: () => customerSignOut(context),
          child: const Text('Switch account / Log out'),
        ),
      ],
    ),
  );
}

class CustomerAccountSecurityScreen extends StatefulWidget {
  final CustomerProfileService? service;
  const CustomerAccountSecurityScreen({super.key, this.service});
  @override
  State<CustomerAccountSecurityScreen> createState() => _SecurityState();
}

class _SecurityState extends State<CustomerAccountSecurityScreen> {
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

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CustomerEditProfileScreen(profileData: _profile, service: _service),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(title: const Text('Account & Security')),
    body: _profile == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: _load,
                    child: const Text('Retry account details'),
                  ),
          )
        : ListView(
            padding: const EdgeInsets.all(10),
            children: [
              AccountGroup(
                title: 'Account',
                children: [
                  AccountRow(label: 'My Profile', onTap: _edit),
                  AccountRow(
                    label: 'Name',
                    value: _profile!['full_name']?.toString() ?? '',
                    onTap: _edit,
                  ),
                  AccountRow(
                    label: 'Phone',
                    value: maskedPhone(_profile!['phone']?.toString() ?? ''),
                    onTap: _edit,
                  ),
                  AccountRow(
                    label: 'Email',
                    value: maskedEmail(_profile!['email']?.toString() ?? ''),
                    subtitle: 'Verified sign-in email',
                  ),
                  AccountRow(
                    label: 'Change Password',
                    subtitle: 'Verify an email code before changing',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CustomerForgotPasswordScreen(
                          initialEmail: _profile!['email']?.toString() ?? '',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AccountGroup(
                title: 'Security',
                children: [
                  AccountRow(
                    label: 'Sign out all devices',
                    subtitle: 'End your account’s refresh sessions',
                    onTap: () => customerSignOut(context, allDevices: true),
                  ),
                ],
              ),
            ],
          ),
  );
}
