import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_home_service.dart';
import '../../services/customer_address_service.dart';
import 'add_address_map_screen.dart';
import '../ai/customer_chatbot_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final CustomerHomeService _homeService = CustomerHomeService();
  final CustomerAddressService _addressService = CustomerAddressService();

  String _currentAddressLabel = 'Choose a service address';
  List<Map<String, dynamic>> _savedAddresses = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _recommendedProviders = [];

  bool _isLoading = true;
  String? _loadError;
  String _activeFilter = 'Location';
  final List<String> _filters = ['Location', 'Upfront Price', 'Rating', '⚡ Emergency'];

  // Gesture Pull & Hold State for AI Assistant
  Timer? _holdTimer;
  double _pullProgress = 0.0;
  bool _isHoldingForAi = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final header = await _homeService.getCustomerHeaderData();
      final categories = await _homeService.getCategories();
      final providers = await _homeService.getRecommendedProviders();
      final addresses = await _addressService.getSavedAddresses();
      if (!mounted) return;
      setState(() {
        _currentAddressLabel = header['address'];
        _categories = categories;
        _recommendedProviders = providers;
        _savedAddresses = addresses;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'Unable to load your services. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onOverscrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels < -30) {
        // User has over-pulled down
        if (!_isHoldingForAi) {
          _isHoldingForAi = true;
          _startAiHoldCountdown();
        }
      } else if (notification.metrics.pixels >= 0 && _isHoldingForAi) {
        _cancelAiHold();
      }
    } else if (notification is ScrollEndNotification) {
      _cancelAiHold();
    }
  }

  void _startAiHoldCountdown() {
    _pullProgress = 0.0;
    _holdTimer?.cancel();

    // 30 tick steps across 3 seconds (100ms per tick)
    int count = 0;
    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      count++;
      if (!mounted) return;
      setState(() {
        _pullProgress = count / 30.0;
      });

      if (count >= 30) {
        timer.cancel();
        _cancelAiHold();
        HapticFeedback.heavyImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomerChatbotScreen()),
        );
      }
    });
  }

  void _cancelAiHold() {
    _holdTimer?.cancel();
    if (_isHoldingForAi) {
      setState(() {
        _isHoldingForAi = false;
        _pullProgress = 0.0;
      });
    }
  }

  void _showAddressPickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Select Service Location',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_savedAddresses.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.location_on, color: CustomerTheme.primary),
                      title: Text(_currentAddressLabel),
                      subtitle: const Text('Default Region: Klang Valley'),
                      trailing: const Icon(Icons.check_circle, color: CustomerTheme.primary),
                    )
                  else
                    ..._savedAddresses.map((addr) {
                      final id = addr['address_id'];
                      final label = addr['label'] ?? 'Address';
                      final line = '${addr['address_line']}, ${addr['city']}';
                      final isSelected = _currentAddressLabel.contains(addr['address_line'] ?? '');

                      return ListTile(
                        leading: Icon(
                          label == 'Home' ? Icons.home_rounded : Icons.business_rounded,
                          color: CustomerTheme.primary,
                        ),
                        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: CustomerTheme.primary)
                            : null,
                        onTap: () async {
                          try {
                            await _addressService.setDefaultAddress(id, line);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (mounted) await _loadDashboardData();
                          } catch (_) {
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Unable to change your address. Please retry.'),
                            ));
                          }
                        },
                      );
                    }),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final newAddr = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddAddressMapScreen()),
                      );
                      if (newAddr != null) {
                        await _loadDashboardData();
                      }
                    },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Add Location from Google Map'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CustomerTheme.background,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _onOverscrollNotification(notification);
          return false;
        },
        child: Stack(
          children: [
            RefreshIndicator(
              color: CustomerTheme.primary,
              onRefresh: _loadDashboardData,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  _buildHeaderSliver(),
                  if (_isLoading)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (_loadError != null)
                    SliverToBoxAdapter(child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Text(_loadError!),
                        TextButton(onPressed: _loadDashboardData, child: const Text('Retry')),
                      ]),
                    )),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          _buildFilterChips(),
                          const SizedBox(height: 24),
                          _buildSectionTitle('Categories', 'View all'),
                          const SizedBox(height: 14),
                          _buildCategoryGrid(),
                          const SizedBox(height: 28),
                          _buildSectionTitle('Verified providers', 'Ordered by rating'),
                          const SizedBox(height: 14),
                          _buildRecommendedCarousel(),
                          const SizedBox(height: 28),
                          _buildSectionTitle('Available services', ''),
                          const SizedBox(height: 14),
                          _buildNearbyList(),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Top Gesture Hold Indicator (AI Assistant summon)
            if (_isHoldingForAi)
              Positioned(
                top: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            value: _pullProgress,
                            strokeWidth: 2.5,
                            color: CustomerTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Hold 3s for AI Assistant...',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Header Banner
  Widget _buildHeaderSliver() {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1E3A8A),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Good day,', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(
                        'weiee',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: _showAddressPickerModal,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 190),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _currentAddressLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'What service do you need today?',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: CustomerTheme.primary),
                    suffixIcon: const Icon(Icons.tune_rounded, color: Colors.grey, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Filter Chips Row
  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _activeFilter == filter;
          final isEmergency = filter.contains('Emergency');

          return ChoiceChip(
            label: Text(filter),
            selected: isSelected,
            onSelected: (_) => setState(() => _activeFilter = filter),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : (isEmergency ? CustomerTheme.danger : CustomerTheme.textPrimary),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
            selectedColor: isEmergency ? CustomerTheme.danger : CustomerTheme.primary,
            backgroundColor: isEmergency ? const Color(0xFFFEE2E2) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: isEmergency ? CustomerTheme.danger : CustomerTheme.borderColor),
            ),
          );
        },
      ),
    );
  }

  // Category Grid
  Widget _buildCategoryGrid() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _categories.map((cat) {
        final String name = cat['category_name'] ?? 'Service';
        final IconData icon = _getCategoryIcon(name);
        final Color color = _getCategoryColor(name);

        return InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Viewing $name specialists...'), duration: const Duration(seconds: 1)),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Icon(icon, color: color, size: 34),
              ),
              const SizedBox(height: 8),
              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // AI Recommended Carousel
  Widget _buildRecommendedCarousel() {
    if (_recommendedProviders.isEmpty) {
      return const Text('No verified providers with available services yet.');
    }
    return SizedBox(
      height: 245,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _recommendedProviders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final p = _recommendedProviders[index];
          final String title = p['business_name'] ?? 'Verified Specialist';
          final double rating = (p['overall_rating'] as num?)?.toDouble() ?? 0.0;
          final double price = (p['base_price'] as num?)?.toDouble() ?? 0.0;
          final String tag = p['match_tag'] ?? 'Verified provider';

          return Container(
            width: 250,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: CustomerTheme.borderColor),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFECFDF5),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, color: CustomerTheme.success, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'Verified Provider',
                        style: TextStyle(color: CustomerTheme.success, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text('★ $rating', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1),
                      const SizedBox(height: 4),
                      Text(p['service_name'] ?? 'Home Maintenance', style: const TextStyle(fontSize: 12, color: CustomerTheme.textSecondary), maxLines: 1),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: CustomerTheme.primarySurface, borderRadius: BorderRadius.circular(8)),
                        child: Text(tag, style: const TextStyle(color: CustomerTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Call-out Fee', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Text('RM${price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: CustomerTheme.primaryDark)),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CustomerTheme.primary,
                              minimumSize: const Size(80, 36),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Book', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Nearby List
  Widget _buildNearbyList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recommendedProviders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final p = _recommendedProviders[index];
        final String name = p['business_name'] ?? 'Technician';
        final double price = (p['base_price'] as num?)?.toDouble() ?? 0.0;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: CustomerTheme.borderColor),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: CustomerTheme.primarySurface,
              child: const Icon(Icons.handyman_rounded, color: CustomerTheme.primary),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Starting from RM${price.toStringAsFixed(0)} • ⭐ ${p['overall_rating'] ?? 0}'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: CustomerTheme.textPrimary)),
        Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CustomerTheme.primary)),
      ],
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'plumbing':
        return Icons.water_drop_rounded;
      case 'electrical':
        return Icons.bolt_rounded;
      case 'cleaning':
        return Icons.cleaning_services_rounded;
      case 'aircon':
      case 'air-conditioning':
        return Icons.ac_unit_rounded;
      default:
        return Icons.home_repair_service_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'plumbing':
        return const Color(0xFF2563EB);
      case 'electrical':
        return const Color(0xFFEAB308);
      case 'cleaning':
        return const Color(0xFF10B981);
      case 'aircon':
      case 'air-conditioning':
        return const Color(0xFF06B6D4);
      default:
        return CustomerTheme.primary;
    }
  }
}
