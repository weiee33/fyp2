import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_auth_service.dart';
import '../home/customer_root_nav_screen.dart';

class CustomerOtpScreen extends StatefulWidget {
  final String email;
  const CustomerOtpScreen({super.key, required this.email});

  @override
  State<CustomerOtpScreen> createState() => _CustomerOtpScreenState();
}

class _CustomerOtpScreenState extends State<CustomerOtpScreen> {
  final _otpController = TextEditingController();
  final _authService = CustomerAuthService();
  bool _loading = false;
  bool _resending = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
      await CustomerDialogs.show(
        context,
        message: 'Please enter the complete code',
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _authService.verifyOtp(email: widget.email, token: code);

      if (!mounted) return;
      await CustomerDialogs.show(
        context,
        title: 'Success',
        message: 'Your email is verified. Your account is ready.',
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CustomerRootNavScreen()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(
        context,
        message: 'Verification Failed: ${e.message}',
      );
    } catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(context, message: 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _resending = true);
    try {
      await _authService.resendOtp(widget.email);
      if (!mounted) return;
      await CustomerDialogs.show(
        context,
        message: 'A new OTP has been dispatched to your email.',
      );
    } catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(context, message: 'Failed to resend: $e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CustomerTheme.lightTheme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Verify Account')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(
                Icons.mark_email_read_outlined,
                size: 64,
                color: CustomerTheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter Verification Code',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'A verification code was sent to:\n${widget.email}',
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
                    : const Text('Verify & Proceed'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _resending ? null : _resendCode,
                child: _resending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Resend Code',
                        style: TextStyle(color: CustomerTheme.primary),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
