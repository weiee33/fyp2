import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _client = Supabase.instance.client;

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone, 'role': 'provider'},
    );
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> logout() async => await _client.auth.signOut();

  Future<void> sendOtp(String email) async {
    await _client.auth.signInWithOtp(email: email);
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
  }
}