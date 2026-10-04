import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAccountService {
  final SupabaseClient? client;
  String? _deletionToken;
  CustomerAccountService({this.client});
  Future<void> deleteAccount(String password) async {
    final supabase = client ?? Supabase.instance.client;
    _deletionToken ??= supabase.auth.currentSession?.accessToken;
    if (_deletionToken == null)
      throw const FormatException('Please sign in again.');
    try {
      final response = await supabase.functions.invoke(
        'customer-delete-account',
        headers: {'Authorization': 'Bearer $_deletionToken'},
        body: {'password': password, 'confirm': 'DELETE'},
      );
      if (response.data is! Map || response.data['deleted'] != true) {
        throw const FormatException(
          'Account deletion has not completed. Please retry.',
        );
      }
    } on FunctionException catch (e) {
      throw FormatException(
        e.details is Map
            ? e.details['error']?.toString() ??
                  'Account deletion failed. Please retry.'
            : 'Account deletion failed. Please retry.',
      );
    }
    // Remote deletion is definitive; a failed local logout must not report a deletion failure.
    try {
      await supabase.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }
}
