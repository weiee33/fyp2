import 'package:fyp2/shared/localization/app_language.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/customer_theme.dart';
import '../../widgets/customer_dialogs.dart';
import '../../services/customer_address_service.dart';
import '../../services/customer_location_service.dart';
import '../../services/provider_coverage_service.dart';

class AddAddressMapScreen extends StatefulWidget {
  final CustomerAddressService? service;
  final ProviderCoverageService? coverageService;
  final Future<LatLng> Function()? locate;
  final Widget Function(BuildContext, ValueChanged<LatLng>)? mapBuilder;
  const AddAddressMapScreen({
    super.key,
    this.service,
    this.coverageService,
    this.locate,
    this.mapBuilder,
  });
  @override
  State<AddAddressMapScreen> createState() => _AddAddressMapScreenState();
}

class _AddAddressMapScreenState extends State<AddAddressMapScreen> {
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  late final _addressService = widget.service ?? CustomerAddressService();
  static const _initialPosition = LatLng(3.1579, 101.7116);
  LatLng _currentPosition = _initialPosition;
  final _searchController = TextEditingController();
  final _addressLineController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postcodeController = TextEditingController();
  String _selectedLabel = 'Home';
  bool _isDefault = true,
      _isFetchingLocation = false,
      _isSaving = false,
      _locating = false;
  bool _mapReady = false;
  Timer? _debounce;
  int _version = 0;
  int _coverageVersion = 0;
  Timer? _coverageDebounce;
  List<ProviderCoverage> _coverage = [];
  ProviderCoverage? _selectedProvider;
  bool _showCoverage = false, _coverageLoading = false;
  String? _coverageError;
  late final _coverageService =
      widget.coverageService ?? ProviderCoverageService();
  Future<void> _loadCoverage() async {
    final version = ++_coverageVersion;
    setState(() {
      _coverageLoading = true;
      _coverageError = null;
    });
    try {
      final rows = await _coverageService.nearby(_currentPosition);
      if (mounted && version == _coverageVersion) {
        setState(() {
          _coverage = rows;
          if (_selectedProvider != null &&
              !rows.any((p) => p.id == _selectedProvider!.id)) {
            _selectedProvider = null;
          }
        });
      }
    } catch (_) {
      if (mounted && version == _coverageVersion) {
        setState(() => _coverageError = 'Coverage unavailable. Tap to retry.');
      }
    } finally {
      if (mounted && version == _coverageVersion) {
        setState(() => _coverageLoading = false);
      }
    }
  }

  void _toggleCoverage() {
    setState(() => _showCoverage = !_showCoverage);
    if (_showCoverage) {
      _loadCoverage();
    } else {
      _coverageDebounce?.cancel();
      _coverageVersion++;
      _coverageLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _myLocation();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _coverageDebounce?.cancel();
    _map.dispose();
    _sheet.dispose();
    for (final c in [
      _searchController,
      _addressLineController,
      _cityController,
      _stateController,
      _postcodeController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _myLocation() async {
    if (_locating) return;
    final version = ++_version;
    _debounce?.cancel();
    setState(() {
      _locating = true;
      _isFetchingLocation = false;
    });
    try {
      final point =
          await (widget.locate ?? CustomerLocationService.currentPosition)();
      if (!mounted || version != _version) return;
      _select(point, move: true);
    } catch (e) {
      if (mounted && version == _version) {
        setState(() => _locating = false);
        await CustomerDialogs.error(context, e);
      }
    } finally {
      if (mounted && version == _version) setState(() => _locating = false);
    }
  }

  void _select(LatLng point, {bool move = false}) {
    _coverageDebounce?.cancel();
    _coverageVersion++;
    if (_showCoverage) {
      _coverageDebounce = Timer(
        const Duration(milliseconds: 600),
        _loadCoverage,
      );
    }

    final version = ++_version;
    _debounce?.cancel();
    setState(() {
      _locating = false;
      _currentPosition = point;
      _isFetchingLocation = true;
    });
    if (move && _mapReady) _centerMap(point, 17);
    _debounce = Timer(
      const Duration(milliseconds: 700),
      () => _lookup(point, version),
    );
  }

  Future<void> _lookup(LatLng point, int version) async {
    final controllers = [
      _addressLineController,
      _cityController,
      _stateController,
      _postcodeController,
    ];
    final before = controllers.map((c) => c.text).toList();
    try {
      final data = await _addressService.reverseGeocode(
        point.latitude,
        point.longitude,
      );
      if (!mounted || version != _version) return;
      final keys = ['addressLine', 'city', 'state', 'postcode'];
      for (var i = 0; i < controllers.length; i++) {
        // Clear missing fields from the previous location, but keep edits made during lookup.
        if (controllers[i].text == before[i]) {
          controllers[i].text = data[keys[i]] ?? '';
        }
      }
      setState(() => _isFetchingLocation = false);
      if ((data['addressLine'] ?? '').isEmpty) {
        await CustomerDialogs.show(
          context,
          message: tr(
            'No address was found for this pin. Please enter the address details.',
          ),
        );
      }
    } catch (e) {
      if (!mounted || version != _version) return;
      for (var i = 0; i < controllers.length; i++) {
        if (controllers[i].text == before[i]) controllers[i].clear();
      }
      setState(() => _isFetchingLocation = false);
      await CustomerDialogs.error(context, e);
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final version = ++_version;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() => _isFetchingLocation = true);
    try {
      final result = await _addressService.searchLocation(query);
      if (!mounted || version != _version) return;
      if (result == null) {
        setState(() => _isFetchingLocation = false);
        await CustomerDialogs.show(
          context,
          message: tr(
            'Address not found in Malaysia. Try a nearby street or building.',
          ),
        );
      } else {
        _select(
          LatLng(result['lat'] as double, result['lng'] as double),
          move: true,
        );
      }
    } catch (e) {
      if (mounted && version == _version) {
        setState(() => _isFetchingLocation = false);
        await CustomerDialogs.error(context, e);
      }
    }
  }

  Future<void> _saveAddress() async {
    if ([
          _addressLineController,
          _cityController,
          _stateController,
          _postcodeController,
        ].any((c) => c.text.trim().isEmpty) ||
        !RegExp(r'^\d{5}$').hasMatch(_postcodeController.text.trim())) {
      await CustomerDialogs.show(
        context,
        message: tr(
          'Please enter the address, city, state and a five-digit Malaysian postcode.',
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final address = await _addressService.addAddress(
        label: _selectedLabel,
        addressLine: _addressLineController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        postcode: _postcodeController.text.trim(),
        latitude: _currentPosition.latitude,
        longitude: _currentPosition.longitude,
        isDefault: _isDefault,
      );
      if (!mounted) return;
      setState(() => _isSaving = false);
      await CustomerDialogs.show(
        context,
        title: tr('Success'),
        message: tr('Address saved successfully.'),
      );
      if (mounted) Navigator.pop(context, address);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        await CustomerDialogs.error(context, e);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _centerMap(LatLng point, double zoom) {
    _map.move(
      point,
      zoom,
      offset: Offset(0, -_map.camera.nonRotatedSize.height * .25),
    );
  }

  void _expandSheet() {
    if (_sheet.isAttached) {
      unawaited(
        _sheet.animateTo(
          .94,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool numeric = false,
  }) => TextField(
    controller: controller,
    onTap: _expandSheet,
    minLines: label == 'Address Line / Unit No.' ? 2 : 1,
    maxLines: label == 'Address Line / Unit No.' ? 3 : 1,
    keyboardType: numeric ? TextInputType.number : TextInputType.streetAddress,
    decoration: InputDecoration(
      labelText: trOrNull(label),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Theme(
      data: CustomerTheme.lightTheme,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Add Service Location'))),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final headerHeight =
                  110.0 +
                  (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                    0,
                    28,
                  );
              final minimum = (headerHeight / bounds.maxHeight).clamp(.14, .46);
              return Stack(
                children: [
                  // Full, fixed map viewport. Sheet gestures never resize or pan its camera.
                  Positioned.fill(
                    child:
                        widget.mapBuilder?.call(context, _select) ??
                        FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: _initialPosition,
                            initialZoom: 16,
                            maxZoom: 19,
                            onMapReady: () {
                              _mapReady = true;
                              _centerMap(_currentPosition, 16);
                            },
                            onTap: (_, point) => _select(point),
                            onPositionChanged: (camera, gesture) {
                              if (gesture) {
                                _select(
                                  camera.screenOffsetToLatLng(
                                    Offset(
                                      camera.nonRotatedSize.width / 2,
                                      camera.nonRotatedSize.height * .25,
                                    ),
                                  ),
                                );
                              }
                            },
                            interactionOptions: const InteractionOptions(
                              flags:
                                  InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: const String.fromEnvironment(
                                'MAP_TILE_URL',
                                defaultValue:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              ),
                              userAgentPackageName: 'com.locallife.fyp2',
                              maxNativeZoom: 19,
                            ),
                            if (_showCoverage)
                              CircleLayer(
                                circles: _coverage
                                    .map(
                                      (p) => CircleMarker(
                                        point: p.centre,
                                        radius: p.radiusKm * 1000,
                                        useRadiusInMeter: true,
                                        color:
                                            (_selectedProvider?.id == p.id
                                                    ? Colors.blue
                                                    : CustomerTheme.primary)
                                                .withValues(alpha: .10),
                                        borderColor:
                                            _selectedProvider?.id == p.id
                                            ? Colors.blue
                                            : CustomerTheme.primary,
                                        borderStrokeWidth:
                                            _selectedProvider?.id == p.id
                                            ? 2
                                            : 1,
                                      ),
                                    )
                                    .toList(),
                              ),
                            MarkerLayer(
                              markers: [
                                if (_showCoverage)
                                  ..._coverage.map(
                                    (p) => Marker(
                                      point: p.centre,
                                      width: 150,
                                      height: 64,
                                      child: Semantics(
                                        label: tr(
                                          "{0}, {1} kilometre service radius",
                                          [p.name, p.radiusKm.toInt()],
                                        ),
                                        button: true,
                                        child: GestureDetector(
                                          onTap: () => setState(
                                            () => _selectedProvider = p,
                                          ),
                                          child: Column(
                                            children: [
                                              const Icon(
                                                Icons.home_repair_service,
                                                color: Colors.blue,
                                                size: 26,
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  p.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Marker(
                                  point: _currentPosition,
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.topCenter,
                                  child: const IgnorePointer(
                                    child: Icon(
                                      Icons.location_pin,
                                      color: CustomerTheme.primary,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _toggleCoverage,
                        icon: Icon(
                          _showCoverage
                              ? Icons.layers_clear_outlined
                              : Icons.layers_outlined,
                        ),
                        label: Text(
                          tr(
                            _showCoverage
                                ? 'Hide service areas'
                                : 'Show service areas',
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_showCoverage)
                    Positioned(
                      top: 62,
                      left: 12,
                      right: 12,
                      child: AnimatedSize(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: Material(
                          color: Colors.white,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_coverageLoading)
                                  const LinearProgressIndicator(),
                                if (_coverageError != null)
                                  InkWell(
                                    onTap: _loadCoverage,
                                    child: Text(tr(_coverageError!)),
                                  )
                                else if (_selectedProvider != null) ...[
                                  Text(
                                    _selectedProvider!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    tr("{0} km radius · {1}", [
                                      _selectedProvider!.radiusKm.toInt(),
                                      tr(
                                        _selectedProvider!.covers(
                                              _currentPosition,
                                            )
                                            ? 'Selected address in range'
                                            : 'Selected address outside range',
                                      ),
                                    ]),
                                  ),
                                  Text(
                                    _selectedProvider!.services.join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ] else
                                  Text(
                                    tr(
                                      _coverage.isEmpty
                                          ? 'No published service areas near this address.'
                                          : tr(
                                              "{0} providers nearby · Tap a blue marker",
                                              [_coverage.length],
                                            ),
                                    ),
                                  ),
                                Text(
                                  tr(
                                    'Provider-declared areas. Confirm availability before booking.',
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  DraggableScrollableSheet(
                    controller: _sheet,
                    initialChildSize: .55,
                    minChildSize: minimum,
                    maxChildSize: .94,
                    snap: true,
                    snapSizes: const [.55],
                    snapAnimationDuration: const Duration(milliseconds: 250),
                    builder: (context, scroll) => Material(
                      key: const ValueKey('address-details-card'),
                      color: Colors.white,
                      elevation: 8,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CustomScrollView(
                        controller: scroll,
                        physics: const ClampingScrollPhysics(),
                        slivers: [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _AddressSearchHeader(
                              height: headerHeight,
                              child: Material(
                                color: Colors.white,
                                child: Column(
                                  children: [
                                    Semantics(
                                      label: tr('Drag to resize address panel'),
                                      child: SizedBox(
                                        key: const ValueKey(
                                          'address-sheet-handle',
                                        ),
                                        height: 24,
                                        width: double.infinity,
                                        child: Center(
                                          child: Container(
                                            width: 38,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade300,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: TextField(
                                        key: const ValueKey(
                                          'address-sheet-search',
                                        ),
                                        controller: _searchController,
                                        onTap: _expandSheet,
                                        textInputAction: TextInputAction.search,
                                        onSubmitted: (_) => _search(),
                                        decoration: InputDecoration(
                                          hintText: trOrNull(
                                            'Search street or building',
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 10,
                                              ),
                                          prefixIcon: const Icon(Icons.search),
                                          suffixIcon: IconButton(
                                            tooltip: trOrNull('Search address'),
                                            onPressed: _search,
                                            icon: const Icon(
                                              Icons.arrow_forward,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Attribution stays visible even when only the search dock is showing.
                                    SizedBox(
                                      height: 26,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () => launchUrl(
                                          Uri.parse(
                                            'https://www.openstreetmap.org/copyright',
                                          ),
                                        ),
                                        child: Text(
                                          tr('© OpenStreetMap contributors'),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                            sliver: SliverList.list(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tr('Address Details'),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _locating ? null : _myLocation,
                                      icon: const Icon(
                                        Icons.my_location,
                                        size: 18,
                                      ),
                                      label: Text(
                                        tr(
                                          _locating
                                              ? 'Locating…'
                                              : 'My location',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_isFetchingLocation || _locating)
                                  const LinearProgressIndicator(),
                                Padding(
                                  padding: EdgeInsets.only(top: 4, bottom: 16),
                                  child: Text(
                                    tr(
                                      'Add your unit or floor number if needed.',
                                    ),
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: ['Home', 'Office', 'Other']
                                      .map(
                                        (label) => ChoiceChip(
                                          label: Text(tr(label)),
                                          selected: _selectedLabel == label,
                                          selectedColor:
                                              CustomerTheme.primarySurface,
                                          onSelected: (_) => setState(
                                            () => _selectedLabel = label,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 20),
                                _field(
                                  _addressLineController,
                                  'Address Line / Unit No.',
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _field(_cityController, 'City'),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _field(
                                        _postcodeController,
                                        'Postcode',
                                        numeric: true,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _field(_stateController, 'State'),
                                const SizedBox(height: 12),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  activeThumbColor: CustomerTheme.primary,
                                  title: Text(
                                    tr('Set as default service address'),
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  value: _isDefault,
                                  onChanged: (value) =>
                                      setState(() => _isDefault = value),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  key: const ValueKey('address-sheet-save'),
                                  onPressed:
                                      _isSaving ||
                                          _isFetchingLocation ||
                                          _locating
                                      ? null
                                      : _saveAddress,
                                  child: _isSaving
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(tr('Save & Select Address')),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AddressSearchHeader extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _AddressSearchHeader({required this.height, required this.child});
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    AppLanguage.watch(context);
    return child;
  }

  @override
  bool shouldRebuild(covariant _AddressSearchHeader oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
