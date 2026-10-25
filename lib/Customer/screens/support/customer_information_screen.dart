import 'package:flutter/material.dart';
import '../../../shared/localization/app_language.dart';
import '../../core/customer_theme.dart';
import '../../widgets/customer_scaffold.dart';
import 'customer_support_screen.dart';

class CustomerInformationScreen extends StatelessWidget {
  final bool privacy;
  const CustomerInformationScreen({super.key, this.privacy = false});
  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final sections = privacy
        ? [
            (
              tr('Information you provide'),
              tr(
                'Local Life Service Assistant uses your account and contact details to maintain your account. Service addresses, booking instructions, messages, reviews and the photos you choose to upload support the features you use. Birthday and gender are optional profile details.',
              ),
            ),
            (
              tr('Bookings and communication'),
              tr(
                'Providers receive the information needed to discuss and fulfil your booking, including its service address and the messages you send them. Your optional birthday and gender are not included in the provider profile view. Support messages and support photos are available to you and authorised administrators.',
              ),
            ),
            (
              tr('Payments and receipts'),
              tr(
                'Payment details are entered through Stripe. Local Life Service Assistant records payment references, amounts and status to manage bookings and receipts; it does not collect your full payment card details in the app. The email address supplied during checkout may be used to deliver your receipt.',
              ),
            ),
            (
              tr('Technology that supports the service'),
              tr(
                'Local Life Service Assistant uses Supabase for account, database and file services, Firebase for supported phone notifications, and email services for transactional messages. When you use the AI assistant, your messages and selected attachments are processed to generate a response. Avoid including sensitive personal information in AI conversations.',
              ),
            ),
            (
              tr('Permissions and your choices'),
              tr(
                'Camera, photo library, location and notification permissions support the features you choose to use. You can change these permissions in your device settings. Disabling a permission may limit its related feature. You can also enter a service address manually.',
              ),
            ),
            (
              tr('Managing your information'),
              tr(
                'You can update your details in Profile & Preferences, manage saved addresses, and request account deletion from Account & Security. Clearing a chat removes your visible history, not the other participant’s copy. Booking, payment and support records may need to remain available for transaction history, dispute handling and applicable obligations.',
              ),
            ),
            (
              tr('Privacy questions'),
              tr(
                'Contact support through Help Centre to ask about your information, request a correction or raise a privacy concern. Include the relevant account or booking context, but never send passwords, verification codes or full payment card details.',
              ),
            ),
          ]
        : [
            (
              tr('Household services, organised'),
              tr(
                'Local Life Service Assistant brings service discovery, provider communication and booking management together. Explore available services, compare provider information and customer reviews, and choose a service that fits your needs.',
              ),
            ),
            (
              tr('From request to completion'),
              tr(
                'Choose your service address and an available appointment, then submit a booking request. Once the provider accepts, complete payment within the time shown in Booking Details. Follow progress in the app and share a review after your service is completed.',
              ),
            ),
            (
              tr('Help when you need it'),
              tr(
                'Use Chat to discuss service details with your provider. For a booking issue, submit a linked support request from Booking Details. Help Centre handles general questions and lets you follow the status of your requests and read support responses.',
              ),
            ),
            (
              tr('AI assistance, with you in control'),
              tr(
                'Local Life Service Assistant AI can help you explore services and plan a booking. AI responses can be inaccurate. Review the provider, price, address and appointment details before confirming any booking or payment.',
              ),
            ),
          ];
    return CustomerScaffold(
      appBar: AppBar(
        toolbarHeight: privacy ? kToolbarHeight : 80,
        title: Text(
          tr(privacy ? 'Privacy' : 'About Local Life Service Assistant'),
          textAlign: TextAlign.center,
          maxLines: 3,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SupportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  privacy
                      ? Icons.privacy_tip_outlined
                      : Icons.home_repair_service_outlined,
                  size: 38,
                  color: CustomerTheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  tr(
                    privacy
                        ? 'Your information and choices'
                        : 'Welcome to Local Life Service Assistant',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    privacy
                        ? 'This notice explains how information is used across Local Life Service Assistant and where you can manage it.'
                        : 'A simpler way to find and manage help for your home.',
                  ),
                  textAlign: TextAlign.justify,
                ),
              ],
            ),
          ),
          for (final (title, body) in sections)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SupportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      body,
                      textAlign: TextAlign.justify,
                      style: const TextStyle(height: 1.55),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomerSupportScreen()),
            ),
            icon: const Icon(Icons.support_agent),
            label: Text(tr('Help Centre')),
          ),
          SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
