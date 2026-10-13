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
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: CustomerTheme.primarySurface,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: CustomerTheme.primary,
              );
            }
            return const TextStyle(
              fontSize: 12,
              color: CustomerTheme.textSecondary,
            );
          }),
        ),
        child: NavigationBar(
          height: 65,
          elevation: 8,
          backgroundColor: Colors.white,
          selectedIndex: _currentIndex < 2 ? _currentIndex : _currentIndex + 1,
          onDestinationSelected: (index) {
            if (index == 2) {
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
                  transitionsBuilder: (_, animation, _, child) =>
                      SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      ),
                ),
              );
              return;
            }
            setState(() {
              _currentIndex = index < 2 ? index : index - 1;
            });
          },
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(
                Icons.explore_rounded,
                color: CustomerTheme.primary,
              ),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: CustomerUnreadBadge(
                kind: 'bookings',
                enabled: widget.pages == null,
                child: const Icon(Icons.receipt_long_outlined),
              ),
              selectedIcon: CustomerUnreadBadge(
                kind: 'bookings',
                enabled: widget.pages == null,
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: CustomerTheme.primary,
                ),
              ),
              label: 'Bookings',
            ),
            const NavigationDestination(icon: AiHalo(), label: 'AI'),
            NavigationDestination(
              icon: CustomerUnreadBadge(
                kind: 'notifications',
                enabled: widget.pages == null,
                child: const Icon(Icons.notifications_none),
              ),
              selectedIcon: CustomerUnreadBadge(
                kind: 'notifications',
                enabled: widget.pages == null,
                child: const Icon(
                  Icons.notifications,
                  color: CustomerTheme.primary,
                ),
              ),
              label: 'Notifications',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: CustomerTheme.primary,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
