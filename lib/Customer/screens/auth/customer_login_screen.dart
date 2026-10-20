import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import '../../../shared/brand/brand_splash.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'customer_forgot_password_screen.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../../shared/mobile_auth_service.dart';
import '../../../shared/mobile_account_home.dart';
import '../../../shared/localization/language_screen.dart';
import 'customer_register_screen.dart';

class CustomerLoginScreen extends StatefulWidget {
  final MobileAuthService? service;
  final Widget Function(MobileAccountRole)? homeBuilder;
  const CustomerLoginScreen({super.key, this.service, this.homeBuilder});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final _authService = widget.service ?? MobileAuthService();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) {
      await CustomerDialogs.show(
        context,
        message: tr('Please correct the highlighted fields.'),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final role = await _authService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => (widget.homeBuilder ?? mobileAccountHome)(role),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      String message = CustomerDialogs.errorMessage(e);
      if (message.contains('Invalid login credentials')) {
        message = 'Incorrect email or password.';
      } else if (message.contains('Email not confirmed')) {
        message = 'Please verify your email address before logging in.';
      }
      await CustomerDialogs.show(context, message: message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Theme(
      data: CustomerTheme.lightTheme,
      child: CustomerScaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(tr('Login')),
          actions: [
            IconButton(
              tooltip: tr('Language / 语言 / Bahasa'),
              icon: const Icon(Icons.language_rounded),
              onPressed: _loading
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LanguageScreen()),
                    ),
            ),
          ],
        ),
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: customerScrollPhysics(context),
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Center(child: HomeServeMark(size: 80)),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        tr('Welcome to Home Serve'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: CustomerTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      tr('Email Address'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_loading,
                      validator: (value) => trOrNull(
                        ((v) => (v == null || !v.contains('@'))
                            ? 'Valid email required'
                            : null)(value),
                      ),
                      decoration: InputDecoration(
                        hintText: trOrNull('name@example.com'),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('Password'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      enabled: !_loading,
                      validator: (value) => trOrNull(
                        ((v) => (v == null || v.length < 6)
                            ? 'Password must be 6+ characters'
                            : null)(value),
                      ),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomerForgotPasswordScreen(
                                    initialEmail: _emailController.text.trim(),
                                  ),
                                ),
                              ),
                        child: Text(tr('Forgot password?')),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loading ? null : _handleLogin,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(tr('Login')),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          tr("New here? "),
                          style: TextStyle(color: CustomerTheme.textSecondary),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CustomerRegisterScreen(
                                        service: widget.service,
                                        homeBuilder: widget.homeBuilder,
                                      ),
                                    ),
                                  );
                                },
                          child: Text(
                            tr('Create Account'),
                            style: TextStyle(
                              color: CustomerTheme.primary,
                              fontWeight: FontWeight.bold,
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
        ),
      ),
    );
  }
}
