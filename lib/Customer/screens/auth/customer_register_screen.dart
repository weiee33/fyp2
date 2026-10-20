import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import '../../../shared/brand/brand_splash.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/malaysia_phone_field.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/customer_theme.dart';
import '../../../shared/mobile_auth_service.dart';
import '../../../shared/mobile_account_home.dart';
import 'customer_otp_screen.dart';

class CustomerRegisterScreen extends StatefulWidget {
  final MobileAuthService? service;
  final Widget Function(MobileAccountRole)? homeBuilder;
  const CustomerRegisterScreen({super.key, this.service, this.homeBuilder});

  @override
  State<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState extends State<CustomerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  late final _authService = widget.service ?? MobileAuthService();
  MobileAccountRole _role = MobileAccountRole.customer;

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
      final registration = await _authService.register(
        email: _emailController.text,
        password: _passwordController.text,
        fullName: _nameController.text,
        phone: _phoneController.text,
        accountRole: _role,
      );
      final res = registration.response;

      if (!mounted) return;

      // Check if user identities are empty (email already taken)
      if (res.user != null && (res.user!.identities?.isEmpty ?? false)) {
        await CustomerDialogs.show(
          context,
          message: tr(
            'This email is already registered. Please sign in or reset your password.',
          ),
        );
        return;
      }

      await CustomerDialogs.show(
        context,
        title: tr('Registration received'),
        message: tr(
          res.session == null
              ? 'Check your email for the verification code to activate your account.'
              : 'Your account is ready.',
        ),
      );
      if (!mounted) return;
      if (registration.role case final role?) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => (widget.homeBuilder ?? mobileAccountHome)(role),
          ),
          (_) => false,
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerOtpScreen(
              email: _emailController.text.trim(),
              service: _authService,
              homeBuilder: widget.homeBuilder,
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      await CustomerDialogs.show(context, message: tr(e.message));
    } catch (e) {
      if (!mounted) return;
      await CustomerDialogs.error(context, e);
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
        appBar: AppBar(title: Text(tr('Create Account'))),
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
                    const Center(child: HomeServeMark(size: 80)),
                    const SizedBox(height: 24),
                    Text(
                      tr('Account type'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final role in MobileAccountRole.values)
                            SizedBox(
                              width: constraints.maxWidth < 320
                                  ? constraints.maxWidth
                                  : (constraints.maxWidth - 12) / 2,
                              child: Semantics(
                                selected: _role == role,
                                child: OutlinedButton.icon(
                                  key: ValueKey('register-${role.name}'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    alignment: Alignment.centerLeft,
                                    backgroundColor: _role == role
                                        ? CustomerTheme.primarySurface
                                        : Colors.white,
                                    foregroundColor: _role == role
                                        ? CustomerTheme.primary
                                        : CustomerTheme.textSecondary,
                                    side: BorderSide(
                                      color: _role == role
                                          ? CustomerTheme.primary
                                          : CustomerTheme.borderColor,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: Icon(
                                    _role == role
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                  ),
                                  label: Text(
                                    tr(
                                      role == MobileAccountRole.customer
                                          ? 'Customer'
                                          : 'Provider',
                                    ),
                                  ),
                                  onPressed: _loading
                                      ? null
                                      : () => setState(() => _role = role),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        _role == MobileAccountRole.customer
                            ? 'Book services for your home.'
                            : 'Offer services and manage your jobs.',
                      ),
                      style: const TextStyle(
                        color: CustomerTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      tr('Full Name'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_loading,
                      validator: (value) => trOrNull(
                        ((v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null)(value),
                      ),
                      decoration: InputDecoration(
                        hintText: trOrNull('Sarah Tan'),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('Email Address'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      enabled: !_loading,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) => trOrNull(
                        ((v) => (v == null || !v.contains('@'))
                            ? 'Valid email required'
                            : null)(value),
                      ),
                      decoration: InputDecoration(
                        hintText: trOrNull('user@example.com'),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('Phone Number'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    MalaysiaPhoneField(
                      controller: _phoneController,
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('Password'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_loading,
                      obscureText: _obscurePassword,
                      validator: (value) => trOrNull(
                        ((v) => (v == null || v.length < 6)
                            ? 'Must be 6+ characters'
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
                          : Text(tr('Register & Verify')),
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
