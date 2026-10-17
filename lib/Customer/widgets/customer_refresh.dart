import 'package:flutter/material.dart';
import '../../shared/app_scroll_behavior.dart';

/// Refresh only from the top edge of the primary, forward vertical list.
/// Nested carousels and reversed conversations must not trigger page reloads.
class CustomerRefresh extends StatelessWidget {
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
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: const AppScrollBehavior(),
    child: RefreshIndicator(
      color: color,
      onRefresh: onRefresh,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      notificationPredicate: (notification) =>
          notification.depth == 0 &&
          notification.metrics.axisDirection == AxisDirection.down,
      child: child,
    ),
  );
}
