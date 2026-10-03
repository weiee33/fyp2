import '../../widgets/customer_dialogs.dart';
import '../../../shared/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_browsing_service.dart';
import '../booking/customer_booking_form_screen.dart';

class CustomerProviderDetailScreen extends StatefulWidget {
  final String providerId;
  final String heroTag;
  final String? selectedServiceId;
  final CustomerBrowsingService? browsingService;

  const CustomerProviderDetailScreen({
    super.key,
    required this.providerId,
    required this.heroTag,
    this.selectedServiceId,
    this.browsingService,
  });

  @override
  State<CustomerProviderDetailScreen> createState() =>
      _CustomerProviderDetailScreenState();
}

class _CustomerProviderDetailScreenState
    extends State<CustomerProviderDetailScreen> {
  late final CustomerBrowsingService _service;
  Map<String, dynamic>? _provider;
  bool _loading = true;
  String? _error;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.browsingService ?? CustomerBrowsingService();
    _fetch();
  }

  Future<void> _fetch() async {
    final request = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.getProviderDetails(widget.providerId);
      if (!mounted || request != _requestVersion) return;
      setState(() => _provider = result);
    } catch (_) {
      if (!mounted || request != _requestVersion) return;
      setState(() => _error = 'Unable to load this provider. Please retry.');
      CustomerDialogs.show(context, title: 'Unable to load', message: _error!);
    } finally {
      if (mounted && request == _requestVersion)
        setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _rows(String field) =>
      ((_provider?[field] as List?) ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final services = _rows('services');
    // Preserve the service selected in search rather than silently changing it.
    final selected = services.indexWhere(
      (s) => s['service_id'] == widget.selectedServiceId,
    );
    if (selected > 0) services.insert(0, services.removeAt(selected));
    final certifications = _rows('certifications');
    final reviews = _rows('reviews');
    final rating = (provider?['overall_rating'] as num?)?.toDouble() ?? 0;
    final reviewCount = (provider?['total_reviews'] as num?)?.toInt() ?? 0;
    return Scaffold(
      backgroundColor: CustomerTheme.background,
      appBar: AppBar(
        title: const Text('Provider details'),
        actions: [
          IconButton(
            tooltip: 'Chat with provider',
            onPressed: _provider == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ConversationScreen(providerId: widget.providerId),
                    ),
                  ),
            icon: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
              TextButton(onPressed: _fetch, child: const Text('Retry')),
            ] else if (provider == null && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'This provider is no longer available. Return to search to find another service.',
                  textAlign: TextAlign.center,
                ),
              )
            else if (provider != null) ...[
              Center(
                child: Hero(
                  tag: widget.heroTag,
                  child: ProviderAvatar(
                    photoUrl: provider['profile_photo_url'] as String?,
                    size: 96,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                provider['business_name'] as String,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified, color: CustomerTheme.success, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Verified provider',
                    style: TextStyle(color: CustomerTheme.success),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                reviewCount == 0
                    ? 'No reviews yet'
                    : '${rating.toStringAsFixed(1)} ★ · $reviewCount reviews',
                textAlign: TextAlign.center,
              ),
              if (provider['city'] != null)
                Text(provider['city'].toString(), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const _Heading('About'),
              Text(
                (provider['bio'] as String?)?.trim().isNotEmpty == true
                    ? provider['bio'] as String
                    : 'No description provided.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (provider['years_experience'] != null)
                    Chip(
                      label: Text(
                        '${provider['years_experience']} years of experience',
                      ),
                    ),
                  if (provider['service_radius_km'] != null)
                    Chip(
                      label: Text(
                        'Service radius: ${provider['service_radius_km']} km',
                      ),
                    ),
                ],
              ),
              if (certifications.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _Heading('Verified credentials'),
                ...certifications.map(
                  (c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.workspace_premium,
                      color: CustomerTheme.success,
                    ),
                    title: Text(c['certification_name'] as String),
                    subtitle: c['issuer'] == null
                        ? null
                        : Text(c['issuer'].toString()),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const _Heading('Available services'),
              if (services.isEmpty)
                const Text('No bookable services are currently available.'),
              if (widget.selectedServiceId != null && selected < 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'The service you selected is no longer available.',
                  ),
                ),
              ...services.map((s) => _serviceCard(s, provider)),
              const SizedBox(height: 24),
              const _Heading('Recent customer reviews'),
              if (reviews.isEmpty) const Text('No reviews yet.'),
              ...reviews.map(
                (review) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                review['customer_name'] as String? ??
                                    'Verified customer',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text('${review['rating_score']} ★'),
                          ],
                        ),
                        if ((review['review_comment'] as String?)?.isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 8),
                          Text(review['review_comment'] as String),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (reviewCount > reviews.length)
                Text(
                  'Showing the latest ${reviews.length} of $reviewCount reviews.',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _serviceCard(
    Map<String, dynamic> service,
    Map<String, dynamic> provider,
  ) {
    final price = (service['base_price'] as num).toDouble();
    final hourly = service['pricing_type'] == 'Hourly';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              service['service_name'] as String,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'RM ${price.toStringAsFixed(2)}${hourly ? '/hour' : ''}',
              style: const TextStyle(
                color: CustomerTheme.primaryDark,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (service['estimated_duration'] != null)
              Text('${service['estimated_duration']} minutes'),
            if ((service['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(service['description'] as String),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading || _error != null
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerBookingFormScreen(
                            serviceData: service,
                            providerData: provider,
                          ),
                        ),
                      );
                      if (mounted) await _fetch();
                    },
              child: const Text('Choose date & book'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}

/// A failed/empty image is never allowed to break discovery navigation.
class ProviderAvatar extends StatelessWidget {
  final String? photoUrl;
  final double size;
  const ProviderAvatar({super.key, this.photoUrl, this.size = 48});
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: CustomerTheme.primarySurface,
      child: Icon(Icons.handyman, color: CustomerTheme.primary, size: size / 2),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: photoUrl?.isNotEmpty == true
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );
  }
}
