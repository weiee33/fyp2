import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import 'customer_home_screen.dart';
import '../profile/customer_profile_screen.dart';

class CustomerRootNavScreen extends StatefulWidget {
  final int initialTab;

  const CustomerRootNavScreen({
    super.key,
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
    _currentIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    // Define the 3 main screens for the bottom navigation
    final screens = [
      const CustomerHomeScreen(),
      _buildPlaceholderTab('Activity & Bookings', Icons.receipt_long_rounded), // To be replaced with actual Bookings module later
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
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded, color: CustomerTheme.primary),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded, color: CustomerTheme.primary),
              label: 'Bookings',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: CustomerTheme.primary),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  /// Placeholder widget for modules still under construction
  Widget _buildPlaceholderTab(String title, IconData icon) {
    return Scaffold(
      backgroundColor: CustomerTheme.background,
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: CustomerTheme.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: CustomerTheme.primaryLight),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: CustomerTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Module integration pending',
              style: TextStyle(color: CustomerTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}