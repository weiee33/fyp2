import '../../services/customer_push_service.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'customer_delete_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/account_widgets.dart';
import '../../widgets/customer_dialogs.dart';
import '../../services/customer_profile_service.dart';
import '../../../shared/portal_entry_screen.dart';
import '../../../shared/chat/chat_inbox_screen.dart';
import '../auth/customer_forgot_password_screen.dart';
import 'customer_edit_profile_screen.dart';
import '../../../shared/localization/language_screen.dart';

Future<void> customerSignOut(BuildContext context) async {
  if (!await CustomerDialogs.confirm(
    context,
    title: tr('Log out?'),
    message: tr('You can sign in again with your email and password.'),
  ))
    return;
  try {
    try {
      await CustomerPushService.instance.unregister();
    } catch (_) {
      // Signing out revokes the session that the delivery worker also checks.
      // A failed token cleanup must not prevent the customer from signing out.
    }
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
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
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: Text(tr('Account Settings'))),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(10),
        children: [
          AccountGroup(
            title: tr('Preferences'),
            children: [
              AccountRow(
                label: tr('Language / 语言 / Bahasa'),
                subtitle: AppLanguage.instance.name,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LanguageScreen()),
                ),
              ),
            ],
          ),
          AccountGroup(
            title: tr('My account'),
            children: [
              AccountRow(
                label: tr('Account & Security'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CustomerAccountSecurityScreen(),
                  ),
                ),
              ),
            ],
          ),
          AccountGroup(
            title: tr('Communication'),
            children: [
              if (CustomerPushService.instance.supported)
                ValueListenableBuilder<String>(
                  valueListenable: CustomerPushService.instance.status,
                  builder: (context, status, _) => AccountRow(
                    label: tr('Phone Alerts'),
                    subtitle: tr(status),
                    onTap: () async {
                      await CustomerPushService.instance.enable();
                      if (!context.mounted) return;
                      await CustomerDialogs.show(
                        context,
                        title: tr('Phone Alerts'),
                        message: tr(
                          CustomerPushService.instance.status.value == 'Enabled'
                              ? 'Important booking and payment alerts are enabled.'
                              : 'Allow Home Serve notifications in your phone settings. If alerts are unavailable, contact support.',
                        ),
                      );
                    },
                  ),
                ),
              AccountRow(
                label: tr('Chats'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatInboxScreen()),
                ),
              ),
            ],
          ),
          AccountGroup(
            title: tr('Support'),
            children: [
              AccountRow(
                label: tr('Help Centre'),
                onTap: () => CustomerDialogs.show(
                  context,
                  title: tr('Booking help'),
                  message: tr(
                    '1. Choose a service and address.\n2. Discuss your preferred time using Chat.\n3. Submit the booking and wait for the provider to accept.\n4. Pay from the accepted booking.\n5. Track progress, then review the completed service.\n\nChat agreements do not reserve a time slot. Always use the booking screen.',
                  ),
                ),
              ),
              AccountRow(
                label: tr('Privacy'),
                onTap: () => CustomerDialogs.show(
                  context,
                  title: tr('Your information'),
                  message: tr(
                    'Providers receive the details needed for your bookings and the messages you send them. Your optional birthday and gender are not part of the provider profile view. Deleting a chat clears your visible history; it does not delete the other person’s copy.',
                  ),
                ),
              ),
              AccountRow(
                label: tr('About Home Serve'),
                onTap: () => CustomerDialogs.show(
                  context,
                  title: tr('Home Serve'),
                  message: tr(
                    'Home Serve\nHousehold services, bookings and provider communication.\n\nFYP mobile application.',
                  ),
                ),
              ),
            ],
          ),
          AccountGroup(
            children: [
              AccountRow(
                label: tr('Logout Your Account'),
                onTap: () => customerSignOut(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: Text(tr('Account & Security'))),
      body: _profile == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: _load,
                      child: Text(tr('Retry account details')),
                    ),
            )
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.all(10),
              children: [
                AccountGroup(
                  title: tr('Account'),
                  children: [
                    AccountRow(label: tr('My Profile'), onTap: _edit),
                    AccountRow(
                      label: tr('Name'),
                      value: _profile!['full_name']?.toString() ?? '',
                      onTap: _edit,
                    ),
                    AccountRow(
                      label: tr('Phone'),
                      value: maskedPhone(_profile!['phone']?.toString() ?? ''),
                      onTap: _edit,
                    ),
                    AccountRow(
                      label: tr('Email'),
                      value: maskedEmail(_profile!['email']?.toString() ?? ''),
                      subtitle: tr('Verified sign-in email'),
                    ),
                    AccountRow(
                      label: tr('Change Password'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerForgotPasswordScreen(
                            requireCurrentPassword: true,
                            initialEmail: _profile!['email']?.toString() ?? '',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                AccountGroup(
                  title: tr('Security'),
                  children: [
                    AccountRow(
                      label: tr('Delete Your Account'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomerDeleteAccountScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
