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
    if (move && _mapReady) _map.move(point, 17);
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

  @override
  Widget build(BuildContext context) => Theme(
    data: CustomerTheme.lightTheme,
    child: Scaffold(
      appBar: AppBar(title: const Text('Add Service Location')),
      body: LayoutBuilder(
        builder: (context, bounds) {
          final initial =
              ((530 * MediaQuery.textScalerOf(context).scale(1) +
                          MediaQuery.paddingOf(context).bottom) /
                      bounds.maxHeight)
                  .clamp(.55, .92);
          return Stack(
            children: [
              // A fixed map viewport: resizing/scrolling the card never changes its camera.
              SizedBox(
                height: (bounds.maxHeight * (1 - initial) * 2 - 20).clamp(
                  bounds.maxHeight * .15,
                  bounds.maxHeight * .6,
                ),
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
                          _map.move(_currentPosition, 16);
                        },
                        onTap: (_, point) => _select(point),
                        onPositionChanged: (camera, gesture) {
                          if (gesture) _select(camera.center);
                        },
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
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
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: Column(
                  children: [
                    Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(12),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          hintText: 'Search street or building',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Search address',
                            onPressed: _search,
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              DraggableScrollableSheet(
                initialChildSize: initial,
                minChildSize: (initial - .12).clamp(.4, .8),
                maxChildSize: .96,
                builder: (context, scroll) => Material(
                  key: const ValueKey('address-details-card'),
                  color: Colors.white,
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          controller: scroll,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                          children: [
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                color: Colors.grey.shade300,
                              ),
                            ),
                            const SizedBox(height: 4),
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
                                  icon: const Icon(Icons.my_location, size: 18),
                                  label: Text(
                                    _locating ? 'Locating…' : 'My location',
                                  ),
                                ),
                                if (_isFetchingLocation || _locating)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'Add your unit or floor number if needed.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            // Label Selector (Home, Office, Other)
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: ['Home', 'Office', 'Other'].map((
                                label,
                              ) {
                                final isSelected = _selectedLabel == label;
                                return ChoiceChip(
                                  label: Text(label),
                                  selected: isSelected,
                                  selectedColor: CustomerTheme.primarySurface,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? CustomerTheme.primary
                                        : CustomerTheme.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  side: BorderSide(
                                    color: isSelected
                                        ? CustomerTheme.primary
                                        : CustomerTheme.borderColor,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _selectedLabel = label),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _addressLineController,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                labelText: 'Address Line / Unit No.',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _cityController,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      labelText: 'City',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _postcodeController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      labelText: 'Postcode',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _stateController,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                labelText: 'State',
                              ),
                            ),
                            const SizedBox(height: 6),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: CustomerTheme.primary,
                              title: const Text(
                                'Set as default service address',
                                style: TextStyle(fontSize: 14),
                              ),
                              value: _isDefault,
                              onChanged: (val) =>
                                  setState(() => _isDefault = val),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          MediaQuery.paddingOf(context).bottom + 4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton(
                              onPressed:
                                  _isSaving || _isFetchingLocation || _locating
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
                            Center(
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  minimumSize: const Size(0, 28),
                                  padding: const EdgeInsets.all(2),
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
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
