import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          tr('About Local Life Service Assistant'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome Banner Card
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _borderOrange),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _lightOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.work_outline,
                      color: _primaryOrange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('Welcome to Local Life Service Assistant'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'Grow your service business, manage bookings, and connect with local customers effortlessly.',
                    ),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildInfoCard(
            title: 'Your business, streamlined',
            content:
            'Local Life Service Assistant brings service listings, smart job matching, customer messaging, and schedule management into one workspace. Showcase your services, upload certifications to build trust, set your coverage radius and working hours, and track your ratings.',
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: 'From job match to payout',
            content:
            'Review incoming booking requests or discover recommended jobs through AI Job Matching. Once you accept a request and the customer completes payment, update your job status as you work and receive payouts directly through your Earnings Dashboard after completion.',
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: 'Communication and support',
            content:
            'Use in-app Chat to confirm service requirements, arrival times, or special instructions with customers. Keep your profile verified and availability up to date to maximize booking opportunities and maintain smooth operations.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required String content}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(title),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(content),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}