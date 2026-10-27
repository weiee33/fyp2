import 'package:supabase_flutter/supabase_flutter.dart';
import '../Customer/widgets/malaysia_phone_field.dart';
import '../Customer/services/customer_access.dart';

enum MobileAccountRole { customer, provider }

/// A registration choice is only a request to the signup trigger. After
/// authentication, navigation always uses the canonical database identity.
class MobileAuthService {
  final SupabaseClient? _providedClient;
  MobileAuthService({SupabaseClient? client}) : _providedClient = client;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;

  MobileAccountRole _roleFromIdentity(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid account identity response');
    }
    final role = switch (value['role']) {
      'customer' => MobileAccountRole.customer,
      'provider' => MobileAccountRole.provider,
      _ => throw const AuthException(
        'This account cannot access the mobile app. Administrators use the website.',
      ),
    };
    CustomerAccess.instance.accept(Map<String, dynamic>.from(value));
    return role;
  }

  /// Supabase Flutter loads its persisted session before startup completes.
  /// Refresh an expired access token before validating the canonical identity.
  /// Unlike a new login, a temporary restore failure must preserve the session
  /// for retry, without exposing any authenticated screen until validation succeeds.
  Future<MobileAccountRole?> restoreSession() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    final userId = session.user.id;
    try {
      if (session.isExpired) {
        await _client.auth.refreshSession().timeout(
          const Duration(seconds: 15),
        );
      }
      if (_client.auth.currentUser?.id != userId) return null;
      final identity = await _client
          .rpc('account_identity')
          .timeout(const Duration(seconds: 15));
      // A late response cannot reopen an account after logout/account switching.
      if (_client.auth.currentUser?.id != userId) return null;
      return _roleFromIdentity(identity);
    } on AuthRetryableFetchException {
      rethrow;
    } on AuthException {
      await _discardRestoredSession(userId);
      return null;
    } on PostgrestException catch (error) {
      if (error.code != '42501') rethrow;
      // A definitive canonical access denial is different from an outage.
      await _discardRestoredSession(userId);
      return null;
    }
  }

  Future<void> _discardRestoredSession(String userId) async {
    if (_client.auth.currentUser?.id != userId) return;
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } finally {
      if (_client.auth.currentSession == null) {
        CustomerAccess.instance.accept(const {});
      }
    }
  }

  Future<MobileAccountRole> resolveRole() async {
    try {
      final value = await _client.rpc('account_identity');
      return _roleFromIdentity(value);
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
