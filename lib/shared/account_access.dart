import 'package:fyp2/shared/localization/app_language.dart';
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
          tr("This account cannot use the {0} portal. ", [
                tr(expectedRole == 'customer' ? 'Customer' : 'Provider'),
              ]) +
              tr(
                'Use the portal for your account; administrators use the website.',
              ),
        );
      }
      return identity;
    } on AuthException {
      await client.auth.signOut(scope: SignOutScope.local);
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        await client.auth.signOut(scope: SignOutScope.local);
      }
      rethrow;
    }
  }
}
