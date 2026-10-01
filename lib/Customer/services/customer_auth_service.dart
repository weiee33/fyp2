import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    return await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'role': 'customer',
      },
    );
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

    final user = response.user;
    if (user == null) {
      throw const AuthException('User credentials not found.');
    }

    // 1. Check cached user metadata
    String? role = user.userMetadata?['role']?.toString().toLowerCase();

    // 2. Query public.users table as a fallback source of truth
    if (role == null || role.isEmpty) {
      final userRow = await _client
          .from('users')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle();
      role = userRow?['role']?.toString().toLowerCase();
    }

    // 3. Strict Customer Role Enforcement
    if (role != 'customer') {
      // Invalidate the session immediately
      await _client.auth.signOut();
      throw AuthException(
        'Access Denied: This account is registered as a ${role?.toUpperCase() ?? 'non-customer'}. Please use the Provider Portal.',
      );
    }

    return response;
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.signup,
    );
  }

  Future<void> resendOtp(String email) async {
    await _client.auth.resend(
      email: email.trim(),
      type: OtpType.signup,
    );
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }
}