import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fresh database identity drives presentation; database guards enforce actions.
class CustomerAccess extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = CustomerAccess();
  bool customer = false, suspended = false, unavailable = false;
  bool get restricted => customer && (suspended || unavailable);
  SupabaseClient? _client;
  Timer? _timer;
  StreamSubscription<AuthState>? _auth;
  bool _refreshing = false;

  void accept(Map<String, dynamic> identity) {
    final nextCustomer = identity['role'] == 'customer';
    final nextSuspended = nextCustomer && identity['is_active'] == false;
    if (customer == nextCustomer &&
        suspended == nextSuspended &&
        !unavailable) {
      return;
    }
    customer = nextCustomer;
    suspended = nextSuspended;
    unavailable = false;
    notifyListeners();
  }

  void initialize(SupabaseClient client) {
    if (_client != null) return;
    _client = client;
    WidgetsBinding.instance.addObserver(this);
    _auth = client.auth.onAuthStateChange.listen((event) {
      if (event.session == null) {
        accept(const {});
      } else {
        unawaited(refresh());
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (customer) unawaited(refresh());
    });
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final client = _client;
    final id = client?.auth.currentUser?.id;
    if (client == null || id == null || _refreshing) return;
    _refreshing = true;
    try {
      final result = await client
          .rpc('account_identity')
          .timeout(const Duration(seconds: 10));
      if (client.auth.currentUser?.id == id) {
        accept(Map<String, dynamic>.from(result as Map));
      }
    } catch (_) {
      if (client.auth.currentUser?.id == id && customer && !unavailable) {
        unavailable = true;
        notifyListeners();
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
    _timer?.cancel();
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
