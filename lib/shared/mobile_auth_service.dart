import 'package:supabase_flutter/supabase_flutter.dart';
import '../Customer/widgets/malaysia_phone_field.dart';

enum MobileAccountRole { customer, provider }

/// A registration choice is only a request to the signup trigger. After
/// authentication, navigation always uses the canonical database identity.
class MobileAuthService {
  final SupabaseClient? _providedClient;
  MobileAuthService({SupabaseClient? client}) : _providedClient = client;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;

  Future<MobileAccountRole> resolveRole() async {
    try {
      final value = await _client.rpc('account_identity');
      final role = value is Map ? value['role'] : null;
      return switch (role) {
        'customer' => MobileAccountRole.customer,
        'provider' => MobileAccountRole.provider,
        _ => throw const AuthException(
          'This account cannot access the mobile app. Administrators use the website.',
        ),
      };
    } catch (_) {
      // A failed identity lookup must not leave a newly authenticated session
      // available to another route or a later account.
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      rethrow;
    }
  }

  Future<MobileAccountRole> login({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return resolveRole();
  }

  Future<({AuthResponse response, MobileAccountRole? role})> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required MobileAccountRole accountRole,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': MalaysiaPhone.international(phone),
        'role': accountRole.name,
      },
    );
    final role = response.session == null ? null : await resolveRole();
    return (response: response, role: role);
  }

  Future<MobileAccountRole> verifyOtp({
    required String email,
    required String token,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.signup,
    );
    return resolveRole();
  }

  Future<void> resendOtp(String email) async {
    await _client.auth.resend(email: email.trim(), type: OtpType.signup);
  }
}
