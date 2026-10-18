import 'package:flutter/material.dart';
import 'customer_scaffold.dart';
import '../../shared/app_scroll_behavior.dart';

/// Refresh only from the top edge of the primary, forward vertical list.
/// Nested carousels and reversed conversations must not trigger page reloads.
class CustomerRefresh extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;
  final bool customer;
  const CustomerRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.customer = true,
  });

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: customer
        ? const CustomerScrollBehavior()
        : const AppScrollBehavior(),
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
