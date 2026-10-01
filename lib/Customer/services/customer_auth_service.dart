import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/account_access.dart';

class CustomerAuthService {
  final SupabaseClient _client;

  CustomerAuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'role': 'customer',
      },
    );
    if (response.session != null) {
      await AccountAccess.requireRole(_client, 'customer');
    }
    return response;
  }

  /// Verifies password AND validates that role == 'customer'
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    await AccountAccess.requireRole(_client, 'customer');

    return response;
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.signup,
    );
    await AccountAccess.requireRole(_client, 'customer');
    return response;
  }

  Future<void> resendOtp(String email) async {
    await _client.auth.resend(email: email.trim(), type: OtpType.signup);
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }
}
