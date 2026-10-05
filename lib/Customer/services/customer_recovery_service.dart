import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../../Provider/core/supabase_config.dart';

/// Deliberately uses HTTP, not GoTrueClient: on web every GoTrueClient for the
/// project joins the same Auth BroadcastChannel, even without persistence.
/// Recovery tokens stay here in memory and are never installed in the app client.
class CustomerRecoveryService {
  final http.Client _http;
  final bool _ownsHttp;
  final String _url, _key;
  final Set<Future<void>> _pending = {};
  String? _verifiedEmail, _recoveryToken;
  bool _closed = false;
  Future<void>? _disposing;

  CustomerRecoveryService({
    http.Client? httpClient,
    String? url,
    String? anonKey,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _url = url ?? SupabaseConfig.url,
       _key = anonKey ?? SupabaseConfig.anonKey;

  void _ensureOpen() {
    if (_closed) throw StateError('Password change was cancelled.');
  }

  Future<T> _operation<T>(Future<T> Function() action) {
    _ensureOpen();
    final result = action();
    final tracked = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _pending.add(tracked);
    unawaited(tracked.whenComplete(() => _pending.remove(tracked)));
    return result;
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> body, {
    String? token,
    String method = 'POST',
  }) async {
    final request = http.Request(method, Uri.parse('$_url$path'))
      ..headers.addAll({
        'apikey': _key,
        'Authorization': 'Bearer ${token ?? _key}',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(body);
    final response = await _http
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 25));
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Expected a JSON object.');
        }
        data = decoded;
      } on FormatException {
        throw const AuthException(
          'The server returned an invalid response. Please retry.',
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        (data['msg'] ??
                data['error_description'] ??
                data['error'] ??
                data['message'] ??
                'Unable to complete the request. Please retry.')
            .toString(),
        statusCode: '${response.statusCode}',
      );
    }
    return data;
  }

  Future<void> _requireCustomer(String token) async {
    final identity = await _request(
      '/rest/v1/rpc/account_identity',
      {},
      token: token,
    );
    if (identity['role'] != 'customer') {
      throw const AuthException('This account cannot use the customer portal.');
    }
  }

  Future<void> _logout(String token, {bool all = false}) async {
    try {
      await _request(
        '/auth/v1/logout?scope=${all ? 'global' : 'local'}',
        {},
        token: token,
      );
    } catch (_) {
      /* Cleanup failure must not misreport a completed password update. */
    }
  }

  Future<void> requestCode(String email) => _operation(() async {
    final result = await _request('/functions/v1/customer-recovery', {
      'email': email.trim().toLowerCase(),
    });
    _ensureOpen();
    if (result['sent'] != true) {
      throw const AuthException(
        'Could not send the verification code. Please retry.',
      );
    }
    final prior = _recoveryToken;
    _recoveryToken = null;
    _verifiedEmail = null;
    if (prior != null) await _logout(prior);
  });

  Future<void> verifyCurrentPassword(String email, String password) =>
      _operation(() async {
        String? token;
        try {
          final response = await _request(
            '/auth/v1/token?grant_type=password',
            {'email': email.trim().toLowerCase(), 'password': password},
          );
          token = response['access_token'] as String?;
          if (token == null) {
            throw const AuthException('Current password is incorrect.');
          }
          _ensureOpen();
          await _requireCustomer(token);
          _ensureOpen();
        } on AuthException catch (e) {
          if (e.statusCode == '400' || e.statusCode == '401') {
            throw const AuthException(
              'Current password is incorrect. Please try again.',
            );
          }
          rethrow;
        } finally {
          if (token != null) await _logout(token);
        }
      });

  Future<void> changePassword({
    required String email,
    required String code,
    required String password,
  }) => _operation(() async {
    final address = email.trim().toLowerCase();
    if (_verifiedEmail != address || _recoveryToken == null) {
      final previous = _recoveryToken;
      _recoveryToken = null;
      _verifiedEmail = null;
      if (previous != null) await _logout(previous);
      _ensureOpen();
      final response = await _request('/auth/v1/verify', {
        'email': address,
        'token': code.trim(),
        'type': 'recovery',
      });
      _recoveryToken = response['access_token'] as String?;
      if (_recoveryToken == null) {
        throw const AuthException('Please request a new verification code.');
      }
      _ensureOpen();
      await _requireCustomer(_recoveryToken!);
      _ensureOpen();
      _verifiedEmail = address;
    }
    _ensureOpen();
    await _request(
      '/auth/v1/user',
      {'password': password},
      token: _recoveryToken,
      method: 'PUT',
    );
    final completedToken = _recoveryToken!;
    _recoveryToken = null;
    _verifiedEmail = null;
    // Global revocation is only permitted after the password update succeeds.
    await _logout(completedToken, all: true);
  });

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    // Let an in-flight password check return its temporary token for cleanup.
    // Every subsequent stage checks _closed before requesting OTP or changing it.
    await Future.wait(_pending.toList());
    final token = _recoveryToken;
    _recoveryToken = null;
    _verifiedEmail = null;
    if (token != null) await _logout(token);
    if (_ownsHttp) _http.close();
  }
}
