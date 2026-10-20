import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/customer_theme.dart';
import '../../../shared/mobile_auth_service.dart';
import '../../../shared/mobile_account_home.dart';

class CustomerOtpScreen extends StatefulWidget {
  final String email;
  final MobileAuthService? service;
  final Widget Function(MobileAccountRole)? homeBuilder;
  const CustomerOtpScreen({
    super.key,
    required this.email,
    this.service,
    this.homeBuilder,
  });

  @override
  State<CustomerOtpScreen> createState() => _CustomerOtpScreenState();
}

class _CustomerOtpScreenState extends State<CustomerOtpScreen> {
  final _otpController = TextEditingController();
  late final _authService = widget.service ?? MobileAuthService();
  bool _loading = false;
  bool _resending = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (_loading || _resending) return;
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
      await CustomerDialogs.show(
        context,
        message: tr('Please enter the complete code'),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final role = await _authService.verifyOtp(
        email: widget.email,
        token: code,
      );

      if (!mounted) return;
      await CustomerDialogs.show(
        context,
        title: tr('Success'),
        message: tr('Your email is verified. Your account is ready.'),
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => (widget.homeBuilder ?? mobileAccountHome)(role),
        ),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(context, message: tr(e.message));
    } catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(context, message: tr("Error: {0}", [e]));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_loading || _resending) return;
    setState(() => _resending = true);
    try {
      await _authService.resendOtp(widget.email);
      if (!mounted) return;
      await CustomerDialogs.show(
        context,
        message: tr('A new OTP has been dispatched to your email.'),
      );
    } catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(
        context,
        message: tr("Failed to resend: {0}", [e]),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Theme(
      data: CustomerTheme.lightTheme,
      child: CustomerScaffold(
        appBar: AppBar(title: Text(tr('Verify Account'))),
        body: ListView(
          physics: customerScrollPhysics(context),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            const Icon(
              Icons.mark_email_read_outlined,
              size: 64,
              color: CustomerTheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              tr('Enter Verification Code'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tr("A verification code was sent to:\n{0}", [widget.email]),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CustomerTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 10,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _verifyOtp,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(tr('Verify & Proceed')),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _resending || _loading ? null : _resendCode,
              child: _resending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      tr('Resend Code'),
                      style: TextStyle(color: CustomerTheme.primary),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
