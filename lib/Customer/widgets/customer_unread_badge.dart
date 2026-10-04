import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/customer_live_updates.dart';
import '../../shared/chat/chat_service.dart';
import '../../shared/chat/chat_inbox_screen.dart';

/// One shared subscription per mounted customer session, regardless of icon count.
class CustomerActivityCounts extends ChangeNotifier {
  static final shared = CustomerActivityCounts();
  Map<String, int> counts = {};
  int _references = 0, _generation = 0;
  bool _loading = false, _pending = false;
  CustomerLiveUpdates? _notifications;
  ChatUpdates? _chat;
  void acquire() {
    if (_references++ > 0) return;
    _generation++;
    _notifications = CustomerLiveUpdates(refresh);
    _chat = ChatUpdates(ChatService(), refresh);
    unawaited(refresh());
  }

  void release() {
    if (--_references > 0) return;
    _generation++;
    _notifications?.dispose();
    _chat?.dispose();
    _notifications = null;
    _chat = null;
    counts = {};
  }

  Future<void> refresh() async {
    if (_references == 0) return;
    if (_loading) {
      _pending = true;
      return;
    }
    _loading = true;
    final generation = _generation;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser?.id;
      final data = user == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              await client.rpc('customer_unread_counts'),
            );
      if (_references > 0 &&
          generation == _generation &&
          user == client.auth.currentUser?.id) {
        counts = data.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        notifyListeners();
      }
    } catch (_) {
      /* Preserve the last known counts during a connection failure. */
    } finally {
      _loading = false;
      if (_pending) {
        _pending = false;
        unawaited(refresh());
      }
    }
  }
}

class CustomerUnreadBadge extends StatefulWidget {
  final String kind;
  final Widget child;
  final bool enabled;
  final CustomerActivityCounts? controller;
  const CustomerUnreadBadge({
    super.key,
    required this.kind,
    required this.child,
    this.enabled = true,
    this.controller,
  });
  @override
  State<CustomerUnreadBadge> createState() => _BadgeState();
}

class _BadgeState extends State<CustomerUnreadBadge> {
  late final controller = widget.controller ?? CustomerActivityCounts.shared;
  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      controller.addListener(_changed);
      controller.acquire();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.enabled) {
      controller.removeListener(_changed);
      controller.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.enabled ? controller.counts[widget.kind] ?? 0 : 0;
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: Colors.red.shade700,
      label: Text(count > 99 ? '99+' : '$count'),
      child: widget.child,
    );
  }
}

class CustomerChatButton extends StatelessWidget {
  final Color? color;
  final bool enabled;
  const CustomerChatButton({super.key, this.color, this.enabled = true});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Chats',
    icon: CustomerUnreadBadge(
      kind: 'chats',
      enabled: enabled,
      child: Icon(Icons.chat_bubble_outline, color: color),
    ),
    onPressed: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatInboxScreen()),
      );
      await CustomerActivityCounts.shared.refresh();
    },
  );
}
