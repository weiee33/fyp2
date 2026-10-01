import 'package:flutter/material.dart';
import '../Customer/screens/auth/customer_login_screen.dart';
import '../Provider/screens/auth/login_screen.dart';

class PortalEntryScreen extends StatelessWidget {
  const PortalEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFF6B00), width: 2),
                ),
                child: const Icon(
                  Icons.home_repair_service_rounded,
                  size: 64,
                  color: Color(0xFFFF6B00),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Local Life Service',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select your portal to continue',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const Spacer(),
              _buildRoleCard(
                context,
                title: 'Consumer Portal',
                subtitle: 'Find, book and pay trusted local services',
                icon: Icons.person_rounded,
                primaryColor: const Color(0xFFFF6B00),
                backgroundColor: const Color(0xFFFFF7ED),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomerLoginScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildRoleCard(
                context,
                title: 'Provider Portal',
                subtitle: 'Manage jobs, availability, and earnings',
                icon: Icons.handyman_rounded,
                primaryColor: const Color(0xFF1E3A8A),
                backgroundColor: const Color(0xFFEFF6FF),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
              const Spacer(),
              const Text(
                'Admin governance is accessible via web dashboard only.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(
      BuildContext context, {
        required String title,
        required String subtitle,
        required IconData icon,
        required Color primaryColor,
        required Color backgroundColor,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: primaryColor,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 18, color: primaryColor),
          ],
        ),
      ),
    );
  }
}