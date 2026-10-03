import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/account_access.dart';

/// Refresh authoritative data on reconnect, app resume and booking notifications.
/// Manual refresh remains available when Realtime cannot connect.
class CustomerLiveUpdates extends WidgetsBindingObserver {
  final Future<void> Function() refresh;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _closed = false;
  CustomerLiveUpdates(this.refresh) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_subscribe());
  }
  Future<void> _subscribe() async {
    try {
      final client = Supabase.instance.client;
      final identity = await AccountAccess.requireRole(client, 'customer');
      if (_closed) return;
      _channel = client
          .channel(
            'customer-updates-${identity['user_id']}-${identityHashCode(this)}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: identity['user_id'],
            ),
            callback: (_) => _schedule(),
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) _schedule();
          });
    } catch (_) {
      /* Initial load and manual refresh display actionable errors. */
    }
  }

  void _schedule() {
    if (_closed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!_closed) unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void dispose() {
    _closed = true;
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    if (channel != null)
      unawaited(Supabase.instance.client.removeChannel(channel));
  }
}
