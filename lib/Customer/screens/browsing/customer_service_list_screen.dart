import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../models/service_item.dart';
import '../../services/customer_browsing_service.dart';
import 'customer_provider_detail_screen.dart';

class CustomerServiceListScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialCategoryId;
  final String? initialKeyword;
  final CustomerBrowsingService? browsingService;

  const CustomerServiceListScreen({
    super.key,
    this.initialCategory,
    this.initialCategoryId,
    this.initialKeyword,
    this.browsingService,
  });

  @override
  State<CustomerServiceListScreen> createState() =>
      _CustomerServiceListScreenState();
}

class _CustomerServiceListScreenState extends State<CustomerServiceListScreen> {
  static const _pageSize = 20;
  late final CustomerBrowsingService _service;
  late final TextEditingController _search;
  List<ServiceItem> _services = [];
  String? _category;
  String? _categoryId;
  String? _city;
  double? _maxPrice;
  double? _minRating;
  String? _error;
  bool _loading = true;
  bool _hasMore = false;
  int _requestVersion = 0;
  String _submittedKeyword = '';

  @override
  void initState() {
    super.initState();
    _service = widget.browsingService ?? CustomerBrowsingService();
    _search = TextEditingController(text: widget.initialKeyword);
    _category = widget.initialCategory;
    _categoryId = widget.initialCategoryId;
    _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool more = false}) async {
    if (more && (_loading || !_hasMore)) return;
    final request = ++_requestVersion;
    final offset = more ? _services.length : 0;
    if (!more) _submittedKeyword = _search.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _services = [];
    });
    try {
      final rows = await _service.searchServices(
        categoryId: _categoryId,
        categoryName: _categoryId == null ? _category : null,
        keyword: _submittedKeyword,
        city: _city,
        maxPrice: _maxPrice,
        minRating: _minRating,
        limit: _pageSize + 1,
        offset: offset,
      );
      // An older query must not replace a newer search/filter result.
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _services = [if (more) ..._services, ...rows.take(_pageSize)];
        _hasMore = rows.length > _pageSize;
      });
    } catch (_) {
      if (!mounted || request != _requestVersion) return;
      setState(
        () => _error =
            'Unable to load services. Check your connection and retry.',
      );
      CustomerDialogs.show(context, title: 'Unable to load', message: _error!);
    } finally {
      if (mounted && request == _requestVersion)
        setState(() => _loading = false);
    }
  }

  Future<void> _showFilters() async {
    final filters = await showModalBottomSheet<_ServiceFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(
        initial: _ServiceFilters(
          city: _city,
          maxPrice: _maxPrice,
          minRating: _minRating,
        ),
      ),
    );
    if (!mounted || filters == null) return;
    setState(() {
      _city = filters.city;
      _maxPrice = filters.maxPrice;
      _minRating = filters.minRating;
    });
    await _fetch();
  }

  void _clearFilters() {
    _search.clear();
    _city = _category = _categoryId = null;
    _maxPrice = _minRating = null;
    _fetch();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CustomerTheme.background,
    appBar: AppBar(title: Text(_category ?? 'All services')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  maxLength: 120,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _fetch(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Search services or providers',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search services',
                      onPressed: () => _fetch(),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Filter services',
                onPressed: _showFilters,
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
        ),
        if (_category != null ||
            _maxPrice != null ||
            _minRating != null ||
            _city != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_category != null) Chip(label: Text(_category!)),
                if (_city != null) Chip(label: Text(_city!)),
                if (_maxPrice != null)
                  Chip(
                    label: Text('Up to RM ${_maxPrice!.toStringAsFixed(2)}'),
                  ),
                if (_minRating != null)
                  Chip(label: Text('${_minRating!.toStringAsFixed(0)}+ stars')),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear filters'),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetch,
            child: ListView(
              key: const PageStorageKey('service-results'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading && _services.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_loading && _error == null && _services.isEmpty) ...[
                  const SizedBox(height: 56),
                  const Icon(
                    Icons.search_off,
                    size: 56,
                    color: CustomerTheme.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No services match your search.',
                    textAlign: TextAlign.center,
                  ),
                  const Text(
                    'Try a different keyword, city or price range.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Show all services'),
                  ),
                ],
                ..._services.map(_serviceCard),
                if (_error != null) ...[
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => _fetch(more: _services.isNotEmpty),
                    child: const Text('Retry'),
                  ),
                ] else if (_hasMore)
                  OutlinedButton(
                    onPressed: _loading ? null : () => _fetch(more: true),
                    child: Text(_loading ? 'Loading…' : 'Load more services'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _serviceCard(ServiceItem service) {
    final hero = 'service-avatar-${service.serviceId}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerProviderDetailScreen(
              providerId: service.providerId,
              heroTag: hero,
              selectedServiceId: service.serviceId,
              browsingService: _service,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: hero,
                child: ProviderAvatar(photoUrl: service.photoUrl, size: 52),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      service.businessName,
                      style: const TextStyle(
                        color: CustomerTheme.textSecondary,
                      ),
                    ),
                    if (service.city?.isNotEmpty == true)
                      Text(service.city!, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      service.ratingLabel,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      service.priceLabel,
                      style: const TextStyle(
                        color: CustomerTheme.primaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (service.durationMinutes != null)
                      Text(
                        '${service.durationMinutes} minutes',
                        style: const TextStyle(fontSize: 12),
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
}

class _ServiceFilters {
  final String? city;
  final double? maxPrice;
  final double? minRating;
  const _ServiceFilters({this.city, this.maxPrice, this.minRating});
}

class _FilterSheet extends StatefulWidget {
  final _ServiceFilters initial;
  const _FilterSheet({required this.initial});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _city;
  late final TextEditingController _price;
  late double? _rating;
  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: widget.initial.city);
    _price = TextEditingController(
      text: widget.initial.maxPrice?.toStringAsFixed(2),
    );
    _rating = widget.initial.minRating;
  }

  @override
  void dispose() {
    _city.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Filter services',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _city,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Provider city',
              hintText: 'Any city',
            ),
          ),
          TextFormField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Maximum listed price (RM)',
              helperText: 'Hourly services show their hourly rate.',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final number = double.tryParse(value.trim());
              return number == null || !number.isFinite || number < 0
                  ? 'Enter a valid price of zero or more.'
                  : null;
            },
          ),
          const SizedBox(height: 20),
          const Text('Minimum rating'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Any'),
                selected: _rating == null,
                onSelected: (_) => setState(() => _rating = null),
              ),
              for (final rating in [1.0, 2.0, 3.0, 4.0, 5.0])
                ChoiceChip(
                  label: Text('${rating.toInt()}+ ★'),
                  selected: _rating == rating,
                  onSelected: (_) => setState(() => _rating = rating),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(
                context,
                _ServiceFilters(
                  city: _city.text.trim().isEmpty ? null : _city.text.trim(),
                  maxPrice: double.tryParse(_price.text.trim()),
                  minRating: _rating,
                ),
              );
            },
            child: const Text('Apply filters'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, const _ServiceFilters()),
            child: const Text('Reset filters'),
          ),
        ],
      ),
    ),
  );
}
