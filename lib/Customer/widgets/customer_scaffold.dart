import 'package:flutter/material.dart';
import '../../shared/app_scroll_behavior.dart';

/// One elastic effect, without Android's additional glow/stretch decoration.
/// Explicit physics are also used by lists inside modal routes.
ScrollPhysics customerScrollPhysics(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
    : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

class CustomerScrollBehavior extends MaterialScrollBehavior {
  const CustomerScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      customerScrollPhysics(context);
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Keeps customer motion local; provider routes retain their existing behavior.
class CustomerScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body, bottomNavigationBar, floatingActionButton;
  final Color? backgroundColor;
  final bool enabled;
  const CustomerScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: enabled
        ? const CustomerScrollBehavior()
        : const AppScrollBehavior(),
    child: Scaffold(
      appBar: appBar,
      body: body,
      backgroundColor: backgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    ),
  );
}
