import 'package:supabase_flutter/supabase_flutter.dart';
import '../../Provider/core/supabase_config.dart';
import '../../shared/account_access.dart';

/// Recovery uses an isolated, non-persisted session. It never signs the main
/// application in before the OTP and customer identity have been checked.
class CustomerRecoveryService {
  final SupabaseClient _client;
  String? _verifiedEmail;
  CustomerRecoveryService({SupabaseClient? client})
    : _client =
          client ??
          SupabaseClient(
            SupabaseConfig.url,
            SupabaseConfig.anonKey,
            authOptions: const AuthClientOptions(
              autoRefreshToken: false,
              authFlowType: AuthFlowType.implicit,
            ),
          );

  Future<void> requestCode(String email) async {
    try {
      final result = await _client.functions.invoke(
        'customer-recovery',
        body: {'email': email.trim().toLowerCase()},
      );
      if (result.data is! Map || result.data['sent'] != true)
        throw const FormatException(
          'Could not send the verification code. Please retry.',
        );
    } on FunctionException catch (e) {
      throw FormatException(
        e.details is Map
            ? e.details['error']?.toString() ?? 'Recovery is unavailable.'
            : 'Recovery is unavailable. Please retry.',
      );
    }
    _verifiedEmail = null;
  }

  Future<void> verifyCurrentPassword(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (response.session == null)
        throw const AuthException('Current password is incorrect.');
      await AccountAccess.requireRole(_client, 'customer');
    } on AuthException {
      throw const AuthException(
        'Current password is incorrect. Please try again.',
      );
    } finally {
      _verifiedEmail = null;
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
  }

  Future<void> changePassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final address = email.trim().toLowerCase();
    if (_verifiedEmail != address || _client.auth.currentSession == null) {
      final response = await _client.auth.verifyOTP(
        email: address,
        token: code.trim(),
        type: OtpType.recovery,
      );
      if (response.session == null) {
        throw const AuthException('Please request a new verification code.');
      }
      await AccountAccess.requireRole(_client, 'customer');
      _verifiedEmail = address;
    }
    await _client.auth.updateUser(UserAttributes(password: password));
    _verifiedEmail = null;
    // The password is already changed. A failed network logout must not turn
    // this into a misleading password-change failure or reuse the consumed OTP.
    try {
      await _client.auth.signOut(scope: SignOutScope.global);
    } catch (_) {}
  }

  Future<void> dispose() => _client.dispose();
}
