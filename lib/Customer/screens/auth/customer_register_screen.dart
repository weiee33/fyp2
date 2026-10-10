import '../../widgets/malaysia_phone_field.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_auth_service.dart';
import 'customer_otp_screen.dart';
import '../home/customer_root_nav_screen.dart';

class CustomerRegisterScreen extends StatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  State<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState extends State<CustomerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  late final _authService = CustomerAuthService();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) {
      await CustomerDialogs.show(
        context,
        message: 'Please correct the highlighted fields.',
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await _authService.register(
        email: _emailController.text,
        password: _passwordController.text,
        fullName: _nameController.text,
        phone: _phoneController.text,
      );

      if (!mounted) return;

      // Check if user identities are empty (email already taken)
      if (res.user != null && (res.user!.identities?.isEmpty ?? false)) {
        await CustomerDialogs.show(
          context,
          message:
              'This email is already registered. Please sign in or reset your password.',
        );
        return;
      }

      await CustomerDialogs.show(
        context,
        title: 'Registration received',
        message: res.session == null
            ? 'Check your email for the verification code to activate your account.'
            : 'Your account is ready.',
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => res.session != null
              ? const CustomerRootNavScreen()
              : CustomerOtpScreen(email: _emailController.text.trim()),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(context, message: 'Auth Error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      await CustomerDialogs.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CustomerTheme.lightTheme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Create Customer Account')),
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Full Name',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                      decoration: const InputDecoration(
                        hintText: 'Sarah Tan',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Email Address',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Valid email required'
                          : null,
                      decoration: const InputDecoration(
                        hintText: 'user@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Phone Number',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    MalaysiaPhoneField(
                      controller: _phoneController,
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Password',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Must be 6+ characters'
                          : null,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _loading ? null : _handleRegister,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Register & Verify'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
