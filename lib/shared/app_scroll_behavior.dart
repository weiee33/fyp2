import 'package:flutter/material.dart';

/// Keep content inside its scroll bounds on every platform. Refresh indicators
/// still receive overscroll notifications, without stretching the entire page.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
