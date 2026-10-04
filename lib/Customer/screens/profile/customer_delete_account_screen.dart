import 'package:flutter/material.dart';
import '../../services/customer_account_service.dart';
import '../../widgets/customer_dialogs.dart';
import '../../../shared/portal_entry_screen.dart';

class CustomerDeleteAccountScreen extends StatefulWidget {
  final CustomerAccountService? service;
  const CustomerDeleteAccountScreen({super.key, this.service});
  @override
  State<CustomerDeleteAccountScreen> createState() => _DeleteState();
}

class _DeleteState extends State<CustomerDeleteAccountScreen> {
  final _password = TextEditingController();
  late final _service = widget.service ?? CustomerAccountService();
  bool _busy = false;
  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      await CustomerDialogs.show(
        context,
        message:
            'Enter your current password to confirm that this is your account.',
      );
      return;
    }
    if (!await CustomerDialogs.confirm(
      context,
      title: 'Permanently delete your account?',
      message:
          'Your login, saved addresses, photo and personal profile will be removed. Your sent chat text and review text will be removed. Anonymized booking, payment and rating records remain for transaction history. This cannot be undone. To use this email again, you must register a new account.',
    ))
      return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _service.deleteAccount(_password.text);
      _password.clear();
      if (!mounted) return;
      setState(() => _busy = false);
      await CustomerDialogs.show(
        context,
        title: 'Account deleted',
        message:
            'Your account has been deleted. You must register again to use Local Life.',
      );
      if (mounted)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PortalEntryScreen()),
          (_) => false,
        );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await CustomerDialogs.error(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Delete your account')),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.person_remove_outlined, size: 48, color: Colors.red),
          const SizedBox(height: 20),
          const Text(
            'This permanently removes your login and personal profile. You cannot sign in again unless you register a new account, even if you reuse the same email.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Finish or cancel active bookings and resolve pending payments or disputes first. Anonymized transaction and rating records are retained.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Current password'),
            autofillHints: const [AutofillHints.password],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _delete,
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(_busy ? 'Deleting account…' : 'Delete my account'),
          ),
        ],
      ),
    ),
  );
}
