import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_browsing_service.dart';
import 'customer_provider_detail_screen.dart';

class CustomerServiceListScreen extends StatefulWidget {
  final String? initialCategory;
  const CustomerServiceListScreen({super.key, this.initialCategory});

  @override
  State<CustomerServiceListScreen> createState() => _CustomerServiceListScreenState();
}

class _CustomerServiceListScreenState extends State<CustomerServiceListScreen> {
  final CustomerBrowsingService _browsingService = CustomerBrowsingService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;

  // Filter States
  double _maxPrice = 500.0;
  double _minRating = 0.0;
  String? _activeCategory;

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
    _fetchServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchServices() async {
    setState(() => _isLoading = true);
    try {
      final results = await _browsingService.searchServices(
        categoryName: _activeCategory,
        keyword: _searchController.text,
        maxPrice: _maxPrice < 500.0 ? _maxPrice : null,
        minRating: _minRating > 0 ? _minRating : null,
      );
      if (mounted) {
        setState(() {
          _services = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(24),
                child: ListView(
                  controller: controller,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const Text('Filter Services', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    // Price Filter
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Maximum Price', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('RM ${_maxPrice.toStringAsFixed(0)}', style: const TextStyle(color: CustomerTheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _maxPrice,
                      min: 50,
                      max: 500,
                      divisions: 9,
                      activeColor: CustomerTheme.primary,
                      onChanged: (val) => setModalState(() => _maxPrice = val),
                    ),
                    const SizedBox(height: 20),

                    // Rating Filter
                    const Text('Minimum Rating', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(5, (index) {
                        final ratingValue = index + 1.0;
                        final isSelected = _minRating == ratingValue;
                        return InkWell(
                          onTap: () => setModalState(() => _minRating = isSelected ? 0.0 : ratingValue),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? CustomerTheme.primary : CustomerTheme.primarySurface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Text('$ratingValue', style: TextStyle(color: isSelected ? Colors.white : CustomerTheme.primaryDark, fontWeight: FontWeight.bold)),
                                Icon(Icons.star, size: 16, color: isSelected ? Colors.white : Colors.orange),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _fetchServices();
                      },
                      child: const Text('Apply Filters'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          _maxPrice = 500.0;
                          _minRating = 0.0;
                          _activeCategory = null;
                        });
                        Navigator.pop(ctx);
                        _fetchServices();
                      },
                      child: const Text('Reset', style: TextStyle(color: CustomerTheme.textSecondary)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CustomerTheme.background,
      appBar: AppBar(
        title: Text(_activeCategory ?? 'All Services'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _fetchServices(),
                      decoration: const InputDecoration(
                        hintText: 'Search services...',
                        prefixIcon: Icon(Icons.search, color: CustomerTheme.textSecondary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _showFilterSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: CustomerTheme.primarySurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tune_rounded, color: CustomerTheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: CustomerTheme.primary))
          : RefreshIndicator(
        color: CustomerTheme.primary,
        onRefresh: _fetchServices,
        child: _services.isEmpty
            ? ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          children: const [
            SizedBox(height: 100),
            Center(child: Icon(Icons.search_off_rounded, size: 64, color: Colors.grey)),
            SizedBox(height: 16),
            Center(child: Text('No services match your criteria.', style: TextStyle(color: Colors.grey))),
          ],
        )
            : ListView.separated(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: _services.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final svc = _services[index];
            final provider = svc['provider_profiles'];
            final user = provider['users'];
            final price = (svc['base_price'] as num).toDouble();
            final rating = (provider['overall_rating'] as num).toDouble();
            final photoUrl = user['profile_photo_url']?.toString() ?? '';
            final pId = provider['provider_id'];

            return GestureDetector(
              onTap: () {
                // Using CupertinoPageRoute for native iOS edge-swipe back logic on both platforms
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => CustomerProviderDetailScreen(
                      providerId: pId,
                      heroTag: 'provider_avatar_$pId',
                    ),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'provider_avatar_$pId',
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: CustomerTheme.primarySurface,
                        backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                        child: photoUrl.isEmpty ? const Icon(Icons.handyman, color: CustomerTheme.primary) : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            svc['service_name'] ?? 'Service',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            provider['business_name'] ?? 'Provider',
                            style: const TextStyle(fontSize: 13, color: CustomerTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.orange, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '$rating (${provider['total_reviews']})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                'RM ${price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: CustomerTheme.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}