import 'package:flutter/material.dart';
import '../../shared/app_scroll_behavior.dart';
import '../agent/agent_surface.dart';
import '../core/customer_theme.dart';

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
  final String? agentScreen;
  final bool agentReady;
  const CustomerScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.enabled = true,
    this.agentScreen,
    this.agentReady = true,
  });

  @override
  Widget build(BuildContext context) =>
      enabled ? CustomerActionTheme(child: _content()) : _content();

  Widget _content() => ScrollConfiguration(
    behavior: enabled
        ? const CustomerScrollBehavior()
        : const AppScrollBehavior(),
    child: agentScreen == null
        ? _scaffold()
        : AgentSurface(
            name: agentScreen!,
            ready: agentReady,
            child: _scaffold(),
          ),
  );
  Widget _scaffold() => Scaffold(
    appBar: appBar,
    body: body,
    backgroundColor: backgroundColor,
    bottomNavigationBar: bottomNavigationBar,
    floatingActionButton: floatingActionButton,
  );
}
