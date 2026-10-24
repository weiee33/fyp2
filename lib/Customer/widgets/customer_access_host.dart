import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/localization/app_language.dart';
import '../../shared/portal_entry_screen.dart';
import '../screens/support/customer_support_screen.dart';
import '../services/customer_access.dart';

final customerNavigatorKey = GlobalKey<NavigatorState>();
final customerAccessObserver = CustomerAccessObserver();
const customerSupportRoute = '/customer-support';

class CustomerAccessObserver extends NavigatorObserver {
  final supportVisible = ValueNotifier(false);
  final _supportRoutes = <Route<dynamic>, bool>{};
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    final allowed = _supportRoutes.putIfAbsent(
      topRoute,
      () =>
          topRoute.settings.name == customerSupportRoute ||
          (topRoute is PopupRoute && _supportRoutes[previousTopRoute] == true),
    );
    // Navigation can happen while widgets build. Publish after that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      supportVisible.value = allowed;
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _supportRoutes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _supportRoutes.remove(route);
  }
}

/// Only passive tab navigation is allowed through the global action blocker.
class SuspensionNavigation extends StatefulWidget {
  final Widget child;
  const SuspensionNavigation({super.key, required this.child});
  static final _regions = <GlobalKey>{};
  static bool contains(Offset point) => _regions.any((key) {
    final context = key.currentContext;
    // An offstage tab bar must never exempt controls on a covering route.
    if (context == null || ModalRoute.of(context)?.isCurrent != true)
      return false;
    final box = context.findRenderObject();
    return box is RenderBox &&
        box.attached &&
        box.hasSize &&
        (box.localToGlobal(Offset.zero) & box.size).contains(point);
  });
  @override
  State<SuspensionNavigation> createState() => _SuspensionNavigationState();
}

class _SuspensionNavigationState extends State<SuspensionNavigation> {
  final _region = GlobalKey();
  @override
  void initState() {
    super.initState();
    SuspensionNavigation._regions.add(_region);
  }

  @override
  void dispose() {
    SuspensionNavigation._regions.remove(_region);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(key: _region, child: widget.child);
}

/// Hit-test the tap recognizer before underlying controls, while letting drag
/// gestures reach their scroll views. Exempt only registered read-only tabs.
class _RestrictionHitRegion extends SingleChildRenderObjectWidget {
  const _RestrictionHitRegion({required super.child});
  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RestrictionRenderBox();
}

class _RestrictionRenderBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (SuspensionNavigation.contains(localToGlobal(position))) return false;
    return super.hitTest(result, position: position);
  }
}

class RestrictedCustomerContent extends StatelessWidget {
  final Widget child;
  final VoidCallback onBlocked;
  const RestrictedCustomerContent({
    super.key,
    required this.child,
    required this.onBlocked,
  });
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(child: ExcludeSemantics(child: child)),
      Positioned.fill(
        child: _RestrictionHitRegion(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onBlocked,
            onLongPress: onBlocked,
            onDoubleTap: onBlocked,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ],
  );
}

class CustomerAccessHost extends StatefulWidget {
  final Widget child;
  const CustomerAccessHost({super.key, required this.child});
  @override
  State<CustomerAccessHost> createState() => _CustomerAccessHostState();
}

class _CustomerAccessHostState extends State<CustomerAccessHost> {
  bool _warningOpen = false;
  Future<void> _help() async {
    if (customerAccessObserver.supportVisible.value) return;
    await customerNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: customerSupportRoute),
        builder: (_) => const CustomerSupportScreen(),
      ),
    );
  }

  Future<void> _warn() async {
    if (_warningOpen) return;
    final context = customerNavigatorKey.currentContext;
    if (context == null) return;
    _warningOpen = true;
    final help = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: customerSupportRoute),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xfffff1f1),
        icon: const Icon(Icons.lock_outline, color: Color(0xffb42318)),
        title: Text(
          tr(
            CustomerAccess.instance.unavailable
                ? 'Unable to verify account access'
                : 'Account suspended',
          ),
          style: const TextStyle(color: Color(0xffb42318)),
        ),
        content: Text(
          tr(
            'Your account is view-only. Go to Help Centre to contact support.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('OK')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Help Centre')),
          ),
        ],
      ),
    );
    _warningOpen = false;
    if (help == true) {
      // The previous route has not published its state until the next frame.
      customerAccessObserver.supportVisible.value = false;
      await _help();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: CustomerAccess.instance,
    builder: (context, _) => ValueListenableBuilder<bool>(
      valueListenable: customerAccessObserver.supportVisible,
      builder: (context, support, _) {
        final access = CustomerAccess.instance;
        if (!access.restricted) return widget.child;
        return Material(
          color: const Color(0xffb42318),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr(
                                access.unavailable
                                    ? 'Unable to verify account access'
                                    : 'Account suspended · View only',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Semantics(
                            label: tr('Refresh'),
                            child: IconButton(
                              onPressed: access.refresh,
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _help,
                            child: Text(tr('Help Centre')),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              await Supabase.instance.client.auth.signOut(
                                scope: SignOutScope.local,
                              );
                              customerNavigatorKey.currentState
                                  ?.pushAndRemoveUntil(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const PortalEntryScreen(),
                                    ),
                                    (_) => false,
                                  );
                            },
                            child: Text(tr('Sign out')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(3, 0, 3, 3),
                    child: support
                        ? widget.child
                        : RestrictedCustomerContent(
                            onBlocked: _warn,
                            child: widget.child,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
