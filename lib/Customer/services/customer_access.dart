import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fresh database identity drives presentation; database guards enforce actions.
class CustomerAccess extends ChangeNotifier with WidgetsBindingObserver {
  CustomerAccess({SupabaseClient? client}) : _client = client;
  static final instance = CustomerAccess();
  bool customer = false, suspended = false, unavailable = false;
  bool denied = false;
  bool get restricted => customer && (suspended || denied);
  SupabaseClient? _client;
  Timer? _timer;
  StreamSubscription<AuthState>? _auth;
  bool _refreshing = false;
  bool _disposed = false;
  int _identityRevision = 0;

  void accept(Map<String, dynamic> identity) {
    _identityRevision++;
    final nextCustomer = identity['role'] == 'customer';
    final nextSuspended = nextCustomer && identity['is_active'] == false;
    if (customer == nextCustomer &&
        suspended == nextSuspended &&
        !unavailable &&
        !denied) {
      return;
    }
    customer = nextCustomer;
    suspended = nextSuspended;
    unavailable = false;
    denied = false;
    notifyListeners();
  }

  void initialize(SupabaseClient client) {
    if (_client != null) return;
    _client = client;
    WidgetsBinding.instance.addObserver(this);
    _auth = client.auth.onAuthStateChange.listen(
      (event) {
        if (event.session == null) {
          accept(const {});
        } else {
          unawaited(refresh());
        }
      },
      onError: (Object error, StackTrace stack) {
        // A transient token-refresh error is not a sign-out event. Recheck
        // access without clearing the persisted session; normal retries follow.
        unawaited(refresh());
      },
    );
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (customer) unawaited(refresh());
    });
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final client = _client;
    final id = client?.auth.currentUser?.id;
    if (client == null || id == null || _refreshing || _disposed) return;
    final revision = _identityRevision;
    bool current() =>
        !_disposed &&
        client.auth.currentUser?.id == id &&
        revision == _identityRevision;
    _refreshing = true;
    try {
      final result = await client
          .rpc('account_identity')
          .timeout(const Duration(seconds: 10));
      if (result is! Map ||
          result['role'] is! String ||
          result['is_active'] is! bool) {
        throw const FormatException('Invalid customer identity response');
      }
      if (customer && result['role'] != 'customer') {
        throw const PostgrestException(
          message: 'Customer access denied',
          code: '42501',
        );
      }
      if (current()) {
        accept(Map<String, dynamic>.from(result));
      }
    } catch (error) {
      if (current() && customer) {
        final accessDenied =
            (error is PostgrestException &&
                const ['42501', 'PGRST301', 'PGRST302'].contains(error.code)) ||
            (error is AuthException && error is! AuthRetryableFetchException);
        final nextDenied = denied || accessDenied;
        final nextUnavailable = !accessDenied;
        if (denied != nextDenied || unavailable != nextUnavailable) {
          denied = nextDenied;
          unavailable = nextUnavailable;
          // A failed request cannot change the last server-confirmed suspension.
          // Network failures are presentation warnings, not account decisions.
          notifyListeners();
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
