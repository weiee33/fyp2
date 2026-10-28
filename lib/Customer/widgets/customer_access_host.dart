import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/localization/app_language.dart';
import '../../shared/portal_entry_screen.dart';
import '../screens/support/customer_support_screen.dart';
import '../services/customer_access.dart';
import '../core/customer_theme.dart';

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
    if (context == null || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
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
  final CustomerAccess? access;
  const CustomerAccessHost({super.key, required this.child, this.access});
  @override
  State<CustomerAccessHost> createState() => _CustomerAccessHostState();
}

class _CustomerAccessHostState extends State<CustomerAccessHost> {
  CustomerAccess get _access => widget.access ?? CustomerAccess.instance;
  bool _warningOpen = false;
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _access.refresh();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Widget _connectionBanner() => Material(
    key: const ValueKey('customer-connection-banner'),
    color: const Color(0xfffff4df),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: Color(0xff805400)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('Connection unavailable'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xff805400),
                    ),
                  ),
                  Text(tr('Check Wi-Fi or mobile data and retry.')),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: CustomerTheme.actionShape,
                foregroundColor: CustomerTheme.primary,
              ),
              onPressed: _retrying ? null : _retry,
              child: Text(tr('Retry')),
            ),
          ],
        ),
      ),
    ),
  );
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
            _access.suspended
                ? 'Account suspended'
                : 'Unable to verify account access',
          ),
          style: const TextStyle(color: Color(0xffb42318)),
        ),
        content: Text(
          tr(
            'Your account is view-only. Go to Help Centre to contact support.',
          ),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: CustomerTheme.actionShape,
              foregroundColor: CustomerTheme.primary,
              side: const BorderSide(color: CustomerTheme.primary),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('OK')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              shape: CustomerTheme.actionShape,
              backgroundColor: CustomerTheme.primary,
              foregroundColor: Colors.white,
            ),
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
    listenable: _access,
    builder: (context, _) => ValueListenableBuilder<bool>(
      valueListenable: customerAccessObserver.supportVisible,
      builder: (context, support, _) {
        final access = _access;
        // Keep the Navigator in the same slot when a connection warning comes
        // and goes, preserving the current page and any unsent form text.
        return Column(
          children: [
            access.customer && access.unavailable
                ? _connectionBanner()
                : const SizedBox.shrink(),
            Expanded(child: _accountContent(access, support)),
          ],
        );
      },
    ),
  );

  Widget _accountContent(CustomerAccess access, bool support) {
    if (!access.restricted) return widget.child;
    return Material(
      color: const Color(0xffb42318),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Equal side slots keep the title on the screen centre.
                      const SizedBox(
                        width: 32,
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          tr(
                            access.suspended
                                ? 'Account suspended · View only'
                                : 'Unable to verify account access',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 32),
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
                          customerNavigatorKey.currentState?.pushAndRemoveUntil(
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
  }
}
