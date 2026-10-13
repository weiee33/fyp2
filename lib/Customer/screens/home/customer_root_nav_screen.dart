import '../../widgets/customer_unread_badge.dart';
import '../notifications/customer_notification_screen.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import 'customer_home_screen.dart';
import '../profile/customer_profile_screen.dart';
import '../booking/customer_bookings_screen.dart';
import '../ai/customer_ai_screen.dart';

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

  @override
  void initState() {
    super.initState();
    // Initialize the starting tab based on the parameter passed
    _currentIndex = widget.initialTab.clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    // Define the 4 main screens for the bottom navigation
    final screens =
        widget.pages ??
        [
          const CustomerHomeScreen(),
          const CustomerBookingsScreen(),
          const CustomerNotificationScreen(),
          const CustomerProfileScreen(),
        ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 88,
          child: Stack(
            children: [
              Positioned.fill(
                top: 20,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .05),
                        blurRadius: 18,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _tab(0, 'Explore', Icons.explore_outlined),
                  _tab(
                    1,
                    'Bookings',
                    Icons.receipt_long_outlined,
                    badge: 'bookings',
                  ),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Open AI assistant',
                      child: InkWell(
                        key: const ValueKey('raised-ai-button'),
                        borderRadius: BorderRadius.circular(40),
                        onTap: _openAi,
                        child: SizedBox(
                          height: 88,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const AiHalo(size: 54),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'AI',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: CustomerTheme.primary,
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
        ),
      ),
    );
  }

  Widget _tab(int index, String label, IconData icon, {String? badge}) {
    final selected = _currentIndex == index;
    final glyph = Icon(
      icon,
      size: 23,
      color: selected ? CustomerTheme.primary : CustomerTheme.textSecondary,
    );
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: () => setState(() => _currentIndex = index),
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 66,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 4,
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
                    label,
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
        ),
      ),
    );
  }

  void _openAi() {
    final reduced = MediaQuery.disableAnimationsOf(context);
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const CustomerAiScreen(),
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
