import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/customer_theme.dart';
import '../../widgets/customer_dialogs.dart';
import '../../services/customer_address_service.dart';
import '../../services/customer_location_service.dart';

class AddAddressMapScreen extends StatefulWidget {
  final CustomerAddressService? service;
  final Future<LatLng> Function()? locate;
  final Widget Function(BuildContext, ValueChanged<LatLng>)? mapBuilder;
  const AddAddressMapScreen({
    super.key,
    this.service,
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
        if (controllers[i].text == before[i])
          controllers[i].text = data[keys[i]] ?? '';
      }
      setState(() => _isFetchingLocation = false);
      if ((data['addressLine'] ?? '').isEmpty) {
        await CustomerDialogs.show(
          context,
          message:
              'No address was found for this pin. Please enter the address details.',
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
          message:
              'Address not found in Malaysia. Try a nearby street or building.',
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
        message:
            'Please enter the address, city, state and a five-digit Malaysian postcode.',
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
        title: 'Success',
        message: 'Address saved successfully.',
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
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: CustomerTheme.lightTheme,
    child: Scaffold(
      appBar: AppBar(title: const Text('Add Service Location')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final headerHeight =
                110.0 +
                (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 28);
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
                            if (gesture)
                              _select(
                                camera.screenOffsetToLatLng(
                                  Offset(
                                    camera.nonRotatedSize.width / 2,
                                    camera.nonRotatedSize.height * .25,
                                  ),
                                ),
                              );
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
                          MarkerLayer(
                            markers: [
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
                                    label: 'Drag to resize address panel',
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
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
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
                                        hintText: 'Search street or building',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                        prefixIcon: const Icon(Icons.search),
                                        suffixIcon: IconButton(
                                          tooltip: 'Search address',
                                          onPressed: _search,
                                          icon: const Icon(Icons.arrow_forward),
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
                                      child: const Text(
                                        '© OpenStreetMap contributors',
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
                                  const Expanded(
                                    child: Text(
                                      'Address Details',
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
                                      _locating ? 'Locating…' : 'My location',
                                    ),
                                  ),
                                ],
                              ),
                              if (_isFetchingLocation || _locating)
                                const LinearProgressIndicator(),
                              const Padding(
                                padding: EdgeInsets.only(top: 4, bottom: 16),
                                child: Text(
                                  'Add your unit or floor number if needed.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: ['Home', 'Office', 'Other']
                                    .map(
                                      (label) => ChoiceChip(
                                        label: Text(label),
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
                                title: const Text(
                                  'Set as default service address',
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
                                    : const Text('Save & Select Address'),
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
  ) => child;
  @override
  bool shouldRebuild(covariant _AddressSearchHeader oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
