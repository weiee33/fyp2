import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

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
          tr('Privacy'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card with Icon
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
                      Icons.shield_outlined,
                      color: _primaryOrange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('Provider data and privacy'),
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
                      'This notice explains how your business, verification, and operational data are handled across Local Life Service Assistant.',
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
            title: 'Business profile and verification',
            content:
            'Local Life Service Assistant uses your business name, contact details, bio, service listings, working hours, and coverage areas to display your profile to customers. Uploaded certifications and identification documents are reviewed strictly by authorised administrators for account verification.',
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: 'Jobs, location, and communication',
            content:
            'When you accept a booking, you receive the customer’s service address and booking instructions needed to complete the job. Your service area radius and availability are used to power AI job matching and scheduling. In-app messages and job photos are accessible to you, the customer, and authorised support administrators.',
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: 'Earnings and payouts',
            content:
            'Customer payments and provider payouts are processed securely through Stripe. Local Life Service Assistant records transaction references, service fees, payout amounts, and settlement statuses to maintain your earnings dashboard and financial records.',
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