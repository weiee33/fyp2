import 'package:flutter/material.dart';
import '../Customer/screens/auth/customer_login_screen.dart';

/// All entry and sign-out paths return to the same role-aware login.
class PortalEntryScreen extends StatelessWidget {
  const PortalEntryScreen({super.key});

  @override
  Widget build(BuildContext context) => const CustomerLoginScreen();
}
