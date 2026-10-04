import 'dart:async';
import 'package:flutter/material.dart';

/// Standard pull-down refresh, plus pull-up at the bottom (including reversed chats).
class CustomerRefresh extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;
  const CustomerRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
  });
  @override
  State<CustomerRefresh> createState() => _CustomerRefreshState();
}

class _CustomerRefreshState extends State<CustomerRefresh> {
  bool _armed = false, _refreshing = false, _bottom = false;
  Future<void> _refresh({bool bottom = false}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _bottom = bottom;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _bottom = false;
        });
      }
    }
  }

  bool _scroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) _armed = false;
    if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        !_refreshing) {
      final m = n.metrics;
      final beyondBottom = m.axisDirection == AxisDirection.up
          ? m.minScrollExtent - m.pixels
          : m.axisDirection == AxisDirection.down
          ? m.pixels - m.maxScrollExtent
          : 0.0;
      if (beyondBottom >= 70) _armed = true;
    }
    if (n is ScrollEndNotification && _armed) {
      _armed = false;
      // Notification can occur during layout; defer visual state updates.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh(bottom: true));
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _scroll,
        child: Stack(
          children: [
            RefreshIndicator(
              color: widget.color,
              onRefresh: _refresh,
              child: widget.child,
            ),
            if (_refreshing && _bottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(color: widget.color),
              ),
          ],
        ),
      );
}
