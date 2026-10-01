import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_browsing_service.dart';
import '../booking/customer_booking_form_screen.dart';
import 'package:flutter/cupertino.dart';

class CustomerProviderDetailScreen extends StatefulWidget {
  final String providerId;
  final String heroTag;

  const CustomerProviderDetailScreen({
    super.key,
    required this.providerId,
    required this.heroTag,
  });

  @override
  State<CustomerProviderDetailScreen> createState() => _CustomerProviderDetailScreenState();
}

class _CustomerProviderDetailScreenState extends State<CustomerProviderDetailScreen> {
  final CustomerBrowsingService _service = CustomerBrowsingService();
  Map<String, dynamic>? _providerData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    final data = await _service.getProviderDetails(widget.providerId);
    if (mounted) {
      setState(() {
        _providerData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: CustomerTheme.background,
        body: Center(child: CircularProgressIndicator(color: CustomerTheme.primary)),
      );
    }

    if (_providerData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Provider Details')),
        body: const Center(child: Text('Provider not found.')),
      );
    }

    final p = _providerData!;
    final user = p['users'];
    final photoUrl = user['profile_photo_url']?.toString() ?? '';
    final rating = (p['overall_rating'] as num).toDouble();
    final isVerified = p['verification_status'] == 'Verified';

    final services = (p['services'] as List?) ?? [];
    final certs = (p['provider_certifications'] as List?) ?? [];
    final reviews = (p['reviews'] as List?) ?? [];

    return Scaffold(
      backgroundColor: CustomerTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Elastic Mobile Header
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true, // Enables elastic pull-down animation
            backgroundColor: CustomerTheme.primaryDark,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [CustomerTheme.primaryDark, CustomerTheme.primaryLight],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Hero(
                      tag: widget.heroTag,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
                        ),
                        child: CircleAvatar(
                          radius: 54,
                          backgroundColor: Colors.white,
                          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                          child: photoUrl.isEmpty ? const Icon(Icons.handyman, size: 50, color: CustomerTheme.primary) : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      p['business_name'] ?? 'Service Provider',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    if (isVerified)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Verified Professional', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatBlock(Icons.star_rounded, '$rating', '${p['total_reviews']} Reviews', Colors.orange),
                      _buildStatBlock(Icons.business_center_rounded, '${p['years_experience'] ?? 0} Yrs', 'Experience', CustomerTheme.primary),
                      _buildStatBlock(Icons.map_rounded, '${p['service_radius_km'] ?? 10} KM', 'Coverage', Colors.green),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // About Section
                  const Text('About', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    p['bio'] ?? 'No description provided.',
                    style: const TextStyle(color: CustomerTheme.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 24),

                  // Certifications[cite: 378]
                  if (certs.isNotEmpty) ...[
                    const Text('Verified Credentials', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...certs.map((c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.workspace_premium, color: CustomerTheme.success),
                      title: Text(c['certification_name']),
                      subtitle: Text('Issued by: ${c['issuer']}'),
                      trailing: c['is_verified']
                          ? const Icon(Icons.check_circle, color: CustomerTheme.success, size: 18)
                          : const Icon(Icons.pending, color: Colors.orange, size: 18),
                    )),
                    const SizedBox(height: 24),
                  ],

                  // Services Available for Booking
                  const Text('Services Offered', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...services.map((svc) => Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(svc['service_name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                              Text(
                                'RM ${svc['base_price']}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: CustomerTheme.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(svc['description'] ?? '', style: const TextStyle(fontSize: 13, color: CustomerTheme.textSecondary)),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) => CustomerBookingFormScreen(
                                      serviceData: svc,
                                      providerData: _providerData!, // Contains provider_id and business_name
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Select & Book'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(height: 24),

                  // Reviews
                  const Text('Customer Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (reviews.isEmpty)
                    const Text('No reviews yet.', style: TextStyle(color: CustomerTheme.textSecondary))
                  else
                    ...reviews.map((r) {
                      final customerName = r['customer_profiles']?['users']?['full_name'] ?? 'Customer';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(radius: 14, backgroundColor: Colors.grey.shade300, child: const Icon(Icons.person, size: 16, color: Colors.white)),
                                const SizedBox(width: 8),
                                Text(customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const Spacer(),
                                const Icon(Icons.star, size: 14, color: Colors.orange),
                                Text(' ${r['rating_score']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(r['review_comment'] ?? '', style: const TextStyle(color: CustomerTheme.textSecondary, fontSize: 13)),
                            const Divider(height: 24),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBlock(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: CustomerTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}