import 'package:flutter/material.dart';

/// Space inside each root tab's scroll content, not outside its viewport.
/// Pushed routes are outside this scope and retain their normal device inset.
class CustomerNavInsets extends InheritedWidget {
  static const barHeight = 80.0;
  static const margin = 12.0;
  static const clearance = 12.0;
  final double bottom;

  const CustomerNavInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomerNavInsets>()?.bottom ??
      MediaQuery.paddingOf(context).bottom;

  @override
  bool updateShouldNotify(CustomerNavInsets oldWidget) =>
      bottom != oldWidget.bottom;
}
