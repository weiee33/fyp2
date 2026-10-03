import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../profile/my_profile_screen.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otp = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;
  bool _resending = false;

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the full 6-digit code')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _auth.verifyOtp(email: widget.email, token: code);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MyProfileScreen()),
            (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification Failed: ${e.message}'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await _auth.sendOtp(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('A new OTP has been sent to your email.'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resend: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Verify Your Account'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(
                Icons.mark_email_read_outlined,
                size: 64,
                color: _primaryColor,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter Verification Code',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'A 6-digit code was sent to:\n${widget.email}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: '000000',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _loading
                      ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                      : const Text(
                    'Verify',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _resending ? null : _resend,
                child: _resending
                    ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text(
                  'Resend OTP',
                  style: TextStyle(color: _primaryColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}