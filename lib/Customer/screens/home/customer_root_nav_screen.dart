import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'dart:ui' as ui;
import '../../services/customer_push_service.dart';
import '../../widgets/customer_nav_insets.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/customer_unread_badge.dart';
import '../notifications/customer_notification_screen.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import 'customer_home_screen.dart';
import '../profile/customer_profile_screen.dart';
import '../booking/customer_bookings_screen.dart';
import '../ai/customer_ai_screen.dart';
import '../../agent/agent_host.dart';
import '../../agent/agent_surface.dart';
import '../../widgets/customer_access_host.dart';

class CustomerRootNavScreen extends StatefulWidget {
  final int initialTab;
  final List<Widget>? pages;

  const CustomerRootNavScreen({
    super.key,
    this.pages,
    this.initialTab = 0, // Defaults to 0 (Explore/Home Tab)
  });

  @override
  State<CustomerRootNavScreen> createState() => _CustomerRootNavScreenState();
}

class _CustomerRootNavScreenState extends State<CustomerRootNavScreen> {
  late int _currentIndex;
  bool _navigationVisible = true;
  double _scrollTravel = 0;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        MediaQuery.accessibleNavigationOf(context)) {
      return false;
    }
    // Only finger-driven movement hides the bar. Programmatic scrolling (for
    // example by the AI agent) and horizontal carousels leave navigation alone.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (notification.metrics.pixels <=
          notification.metrics.minScrollExtent + 8) {
        _scrollTravel = 0;
        if (!_navigationVisible) setState(() => _navigationVisible = true);
      } else if (!notification.metrics.outOfRange && delta != 0) {
        if (_scrollTravel.sign != delta.sign) _scrollTravel = 0;
        _scrollTravel += delta;
        if (_scrollTravel.abs() >= 18) {
          final visible = _scrollTravel < 0;
          if (_navigationVisible != visible) {
            setState(() => _navigationVisible = visible);
          }
          _scrollTravel = 0;
        }
      }
    } else if (notification is ScrollEndNotification) {
      _scrollTravel = 0;
    }
    return false;
  }

  void _selectTab(int index) => setState(() {
    _currentIndex = index;
    _navigationVisible = true;
    _scrollTravel = 0;
  });

  @override
  void initState() {
    super.initState();
    // Initialize the starting tab based on the parameter passed
    _currentIndex = widget.initialTab.clamp(0, 3);
    if (widget.pages == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) CustomerPushService.instance.activate(context);
      });
    }
  }

  @override
  void dispose() {
    if (widget.pages == null) CustomerPushService.instance.detach(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    // Define the 4 main screens for the bottom navigation
    final screens =
        widget.pages ??
        [
          const CustomerHomeScreen(),
          const CustomerBookingsScreen(),
          const CustomerNotificationScreen(),
          const CustomerProfileScreen(),
        ];

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomGap =
        MediaQuery.viewPaddingOf(context).bottom + CustomerNavInsets.margin;
    return CustomerScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomerNavInsets(
            bottom: keyboardOpen
                ? 0
                : bottomGap +
                      CustomerNavInsets.barHeight +
                      CustomerNavInsets.clearance,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: screens[_currentIndex],
            ),
          ),
          if (!keyboardOpen)
            Positioned(
              left: CustomerNavInsets.margin,
              right: CustomerNavInsets.margin,
              bottom: bottomGap,
              child: IgnorePointer(
                ignoring:
                    !_navigationVisible &&
                    !MediaQuery.accessibleNavigationOf(context),
                child: ExcludeSemantics(
                  excluding:
                      !_navigationVisible &&
                      !MediaQuery.accessibleNavigationOf(context),
                  child: AnimatedSlide(
                    key: const ValueKey('customer-navigation-slide'),
                    offset:
                        _navigationVisible ||
                            MediaQuery.accessibleNavigationOf(context)
                        ? Offset.zero
                        : Offset(
                            0,
                            1 + (bottomGap + 24) / CustomerNavInsets.barHeight,
                          ),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity:
                          _navigationVisible ||
                              MediaQuery.accessibleNavigationOf(context)
                          ? 1
                          : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: _navigation(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navigation() => SizedBox(
    key: const ValueKey('customer-floating-navigation'),
    height: CustomerNavInsets.barHeight,
    child: Stack(
      children: [
        Positioned.fill(
          top: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .84),
                        Colors.white.withValues(alpha: .68),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .85),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _tab(0, 'Explore', Icons.explore_outlined),
            _tab(1, 'Bookings', Icons.receipt_long_outlined, badge: 'bookings'),
            Expanded(
              child: Semantics(
                button: true,
                label: tr('Open AI assistant'),
                child: InkWell(
                  key: const ValueKey('raised-ai-button'),
                  customBorder: const CircleBorder(),
                  onTap: _openAi,
                  child: SizedBox(
                    height: 80,
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: CustomerTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: CustomerTheme.primary.withValues(
                                  alpha: .3,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr('AI'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: CustomerTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _tab(
              2,
              'Notifications',
              Icons.notifications_none,
              badge: 'notifications',
            ),
            _tab(3, 'Profile', Icons.person_outline_rounded),
          ],
        ),
      ],
    ),
  );

  Widget _tab(int index, String label, IconData icon, {String? badge}) {
    final selected = _currentIndex == index;
    final glyph = Icon(
      icon,
      size: 23,
      color: selected ? CustomerTheme.primary : CustomerTheme.textSecondary,
    );
    return Expanded(
      child: SuspensionNavigation(
        child: Semantics(
          selected: selected,
          button: true,
          child:
              InkWell(
                onTap: () => _selectTab(index),
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? CustomerTheme.primarySurface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: badge == null
                            ? glyph
                            : CustomerUnreadBadge(
                                kind: badge,
                                enabled: widget.pages == null,
                                child: glyph,
                              ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tr(label),
                          style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? CustomerTheme.primary
                                : CustomerTheme.textSecondary,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ).agent(
                label,
                capability: index < 2
                    ? AgentCapability.click
                    : AgentCapability.handoff,
              ),
        ),
      ),
    );
  }

  void _openAi() {
    final reduced = MediaQuery.disableAnimationsOf(context);
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => CustomerAiScreen(
          onStartAgent: (goal) async {
            if (!mounted) return;
            _selectTab(0);
            final agent = AgentHost.of(context);
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (mounted) await agent?.run(goal);
          },
        ),
        transitionDuration: reduced
            ? Duration.zero
            : const Duration(milliseconds: 350),
        reverseTransitionDuration: reduced
            ? Duration.zero
            : const Duration(milliseconds: 250),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
      ),
    );
  }
}
