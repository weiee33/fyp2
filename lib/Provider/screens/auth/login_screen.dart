import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import 'register_screen.dart';
import '../profile/my_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();

  bool _loading = false;
  bool _obscurePassword = true;

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // ========== Validators ==========
  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) return 'Please enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  // ========== Login Logic ==========
  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _loading = true);
    try {
      await _auth.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyProfileScreen()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login Error: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Provider Login',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // ---- Icon ----
                const Center(
                  child: Icon(
                    Icons.verified_user_rounded,
                    size: 64,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Title ----
                const Center(
                  child: Text(
                    'Welcome to Local Life',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // ---- Subtitle ----
                const Center(
                  child: Text(
                    'Sign in to offer your services',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ---- Email ----
                const Text(
                  'Email Address',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !_loading,
                  validator: _validateEmail,
                  decoration: _inputDecoration(
                    hint: 'name@example.com',
                    icon: Icons.email_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Password ----
                const Text(
                  'Password',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  enabled: !_loading,
                  validator: _validatePassword,
                  onFieldSubmitted: (_) => _login(),
                  decoration: _inputDecoration(
                    hint: '••••••••',
                    icon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ---- Login Button ----
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                        : const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Register Link ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'New here? ',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Create Account',
                        style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
    );
  }

  // ========== Reusable Input Decoration ==========
  // Aligned with Customer Login style: outlined, rounded, light grey border
  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}