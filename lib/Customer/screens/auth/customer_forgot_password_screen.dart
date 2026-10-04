import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_recovery_service.dart';
import '../../widgets/customer_dialogs.dart';
import 'customer_login_screen.dart';

class CustomerForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  final CustomerRecoveryService? service;
  const CustomerForgotPasswordScreen({
    super.key,
    this.initialEmail = '',
    this.service,
  });
  @override
  State<CustomerForgotPasswordScreen> createState() => _RecoveryState();
}

class _RecoveryState extends State<CustomerForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController(),
      _confirm = TextEditingController(),
      _code = TextEditingController();
  late final _service = widget.service ?? CustomerRecoveryService();
  bool _sent = false, _busy = false, _obscure = true;
  int _seconds = 0;
  Timer? _timer;
  void _cooldown() {
    _seconds = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _seconds <= 1) {
        timer.cancel();
      }
      if (mounted) setState(() => _seconds = (_seconds - 1).clamp(0, 60));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_email, _password, _confirm, _code]) {
      c.clear();
      c.dispose();
    }
    unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _request() async {
    if (_busy) return;
    if (!_sent && !_form.currentState!.validate()) {
      setState(() => _busy = false);
      await CustomerDialogs.show(
        context,
        message: 'Please correct the highlighted fields.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.requestCode(_email.text);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _code.clear();
        _cooldown();
      });
      setState(() => _busy = false);
      await CustomerDialogs.show(
        context,
        title: 'Check your email',
        message:
            'If this email has an account, a verification code will arrive shortly. Check your inbox and spam folder. Your password has not changed yet.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await CustomerDialogs.error(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (!RegExp(r'^\d{6,10}$').hasMatch(_code.text.trim())) {
      setState(() => _busy = false);
      await CustomerDialogs.show(
        context,
        message: 'Enter the complete verification code from your latest email.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.changePassword(
        email: _email.text,
        code: _code.text,
        password: _password.text,
      );
      _password.clear();
      _confirm.clear();
      _code.clear();
      if (!mounted) return;
      setState(() => _busy = false);
      await CustomerDialogs.show(
        context,
        title: 'Password changed',
        message: 'Your new password is ready. Please sign in again.',
      );
      if (widget.service == null) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CustomerLoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await CustomerDialogs.error(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: CustomerTheme.lightTheme,
    child: Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_reset,
                  size: 56,
                  color: CustomerTheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _sent ? 'Verify your email' : 'Choose your new password',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _sent
                      ? 'Enter the latest code sent to ${_email.text.trim()}.'
                      : 'We will email a code to confirm that this account belongs to you.',
                ),
                const SizedBox(height: 24),
                if (!_sent) ...[
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                    validator: (v) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Enter a valid email address',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      helperText: 'Use 12–128 characters',
                      suffixIcon: IconButton(
                        tooltip: 'Show or hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (v) => (v?.length ?? 0) >= 12 && v!.length <= 128
                        ? null
                        : 'Use 12–128 characters',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                    validator: (v) =>
                        v == _password.text ? null : 'Passwords must match',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _request,
                    child: const Text('Confirm change password'),
                  ),
                ] else ...[
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Email verification code',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: const Text('Verify & change password'),
                  ),
                  TextButton(
                    onPressed: _busy || _seconds > 0 ? null : _request,
                    child: Text(
                      _seconds > 0
                          ? 'Resend code in ${_seconds}s'
                          : 'Send a new code',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _sent = false;
                            _code.clear();
                          }),
                    child: const Text('Change email or password'),
                  ),
                ],
                if (_busy) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
