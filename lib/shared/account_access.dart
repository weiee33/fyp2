import 'package:supabase_flutter/supabase_flutter.dart';

/// Navigation follows the database identity; RLS remains the authority.
class AccountAccess {
  static Future<Map<String, dynamic>> requireRole(
    SupabaseClient client,
    String expectedRole,
  ) async {
    try {
      final identity = Map<String, dynamic>.from(
        await client.rpc('account_identity') as Map,
      );
      if (identity['role'] != expectedRole) {
        throw AuthException(
          'This account cannot use the $expectedRole portal. '
          'Use the portal for your account; administrators use the website.',
        );
      }
      return identity;
    } catch (_) {
      await client.auth.signOut(scope: SignOutScope.local);
      rethrow;
    }
  }
}
