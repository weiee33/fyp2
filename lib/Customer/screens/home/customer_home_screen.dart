import '../../widgets/customer_unread_badge.dart';
import '../../widgets/customer_refresh.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_home_service.dart';
import '../../services/customer_address_service.dart';
import '../../services/customer_browsing_service.dart';
import 'add_address_map_screen.dart';
import '../browsing/customer_service_list_screen.dart';
import '../browsing/customer_provider_detail_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  final CustomerHomeService? homeService;
  final CustomerAddressService? addressService;
  final CustomerBrowsingService? browsingService;
  const CustomerHomeScreen({
    super.key,
    this.homeService,
    this.addressService,
    this.browsingService,
  });

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  late final CustomerHomeService _homeService;
  late final CustomerAddressService _addressService;
  final _search = TextEditingController();
  String _address = 'Choose a service address';
  String _name = 'Customer';
  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;
  String? _error;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _homeService = widget.homeService ?? CustomerHomeService();
    _addressService = widget.addressService ?? CustomerAddressService();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _homeService.getCustomerHeaderData(),
        _homeService.getCategories(),
        _homeService.getRecommendedProviders(),
        _addressService.getSavedAddresses(),
      ]);
      if (!mounted || request != _requestVersion) return;
      final header = result[0] as Map<String, dynamic>;
      setState(() {
        _name = header['name'] as String? ?? 'Customer';
        _address = header['address'] as String;
        _categories = result[1] as List<Map<String, dynamic>>;
        _providers = result[2] as List<Map<String, dynamic>>;
        _addresses = result[3] as List<Map<String, dynamic>>;
      });
    } catch (_) {
      if (!mounted || request != _requestVersion) return;
      setState(
        () => _error =
            'Unable to load your services. Check your connection and retry.',
      );
      CustomerDialogs.show(context, title: 'Unable to load', message: _error!);
    } finally {
      if (mounted && request == _requestVersion)
        setState(() => _loading = false);
    }
  }

  void _browse({String? category, String? categoryId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerServiceListScreen(
          initialCategory: category,
          initialCategoryId: categoryId,
          initialKeyword: category == null ? _search.text.trim() : null,
          browsingService: widget.browsingService,
        ),
      ),
    );
  }

  Future<void> _pickAddress() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Service address',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close addresses',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                children: [
                  if (_addresses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Add an address to use when making a booking.',
                      ),
                    ),
                  ..._addresses.map(
                    (address) => ListTile(
                      leading: const Icon(
                        Icons.location_on_outlined,
                        color: CustomerTheme.primary,
                      ),
                      title: Text(address['label'] as String? ?? 'Address'),
                      subtitle: Text(
                        '${address['address_line']}, ${address['city']}',
                      ),
                      trailing: address['is_default'] == true
                          ? const Icon(
                              Icons.check_circle,
                              color: CustomerTheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(
                        sheetContext,
                        address['address_id'] as String,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(sheetContext, 'add'),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add service address'),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'add') {
      final address = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AddAddressMapScreen()),
      );
      if (mounted && address != null) await _load();
      return;
    }
    try {
      await _addressService.setDefaultAddress(selected, '');
      if (mounted) await _load();
    } catch (_) {
      if (mounted)
        CustomerDialogs.show(
          context,
          message: 'Unable to change your address. Please retry.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CustomerTheme.background,
    body: CustomerRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          _header(),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Service categories',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _search.clear();
                          _browse();
                        },
                        child: const Text('View all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_categories.isEmpty)
                    const Text('No service categories are available yet.'),
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final columns = constraints.maxWidth >= 500 ? 4 : 3;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 8) / columns;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 12,
                        children: _categories
                            .map(
                              (category) => SizedBox(
                                width: width,
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _browse(
                                      category:
                                          category['category_name'] as String,
                                      categoryId:
                                          category['category_id'] as String,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 14,
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            _categoryIcon(
                                              category['category_name']
                                                  as String,
                                            ),
                                            color: CustomerTheme.primary,
                                            size: 32,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            category['category_name'] as String,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Verified providers',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ordered by customer rating',
                    style: TextStyle(color: CustomerTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (_providers.isEmpty)
                    const Text(
                      'No verified providers with available services yet.',
                    ),
                  ..._providers.map(_providerCard),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _search.clear();
                      _browse();
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('Browse all services'),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [CustomerTheme.primaryDark, CustomerTheme.primary],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Good day,',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    _name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const CustomerChatButton(color: Colors.white),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _loading ? null : _pickAddress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const Icon(Icons.expand_more, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          maxLength: 120,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _browse(),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'What service do you need?',
            prefixIcon: const Icon(Icons.search, color: CustomerTheme.primary),
            suffixIcon: IconButton(
              tooltip: 'Search services',
              onPressed: () => _browse(),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _providerCard(Map<String, dynamic> provider) {
    final count = (provider['total_reviews'] as num?)?.toInt() ?? 0;
    final rating = (provider['overall_rating'] as num?)?.toDouble() ?? 0;
    final price = (provider['base_price'] as num).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerProviderDetailScreen(
              providerId: provider['provider_id'] as String,
              heroTag: 'home-provider-${provider['provider_id']}',
              browsingService: widget.browsingService,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProviderAvatar(
                photoUrl: provider['image_url'] as String?,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider['business_name'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      provider['service_name'] as String,
                      style: const TextStyle(
                        color: CustomerTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      count == 0
                          ? 'No reviews yet'
                          : '${rating.toStringAsFixed(1)} ★ · $count reviews',
                    ),
                    Text(
                      'From RM ${price.toStringAsFixed(2)}${provider['pricing_type'] == 'Hourly' ? '/hour' : ''}',
                      style: const TextStyle(
                        color: CustomerTheme.primaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'View services & book',
                      style: TextStyle(color: CustomerTheme.primaryDark),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: CustomerTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'plumbing':
        return Icons.water_drop_outlined;
      case 'electrical':
        return Icons.bolt;
      case 'cleaning':
        return Icons.cleaning_services;
      case 'aircon':
      case 'air-conditioning':
        return Icons.ac_unit;
      default:
        return Icons.home_repair_service_outlined;
    }
  }
}
