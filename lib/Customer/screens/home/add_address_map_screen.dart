import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_address_service.dart';

class AddAddressMapScreen extends StatefulWidget {
  const AddAddressMapScreen({super.key});

  @override
  State<AddAddressMapScreen> createState() => _AddAddressMapScreenState();
}

class _AddAddressMapScreenState extends State<AddAddressMapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final CustomerAddressService _addressService = CustomerAddressService();

  // Default coordinate: Kuala Lumpur City Center
  static const LatLng _initialPosition = LatLng(3.1579, 101.7116);
  LatLng _currentPosition = _initialPosition;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addressLineController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _postcodeController = TextEditingController();

  String _selectedLabel = 'Home';
  bool _isDefault = true;
  bool _isFetchingLocation = false;
  bool _isSaving = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _triggerReverseGeocode(_initialPosition.latitude, _initialPosition.longitude);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _addressLineController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postcodeController.dispose();
    super.dispose();
  }

  void _onCameraMove(CameraPosition position) {
    _currentPosition = position.target;
  }

  void _onCameraIdle() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      _triggerReverseGeocode(_currentPosition.latitude, _currentPosition.longitude);
    });
  }

  Future<void> _triggerReverseGeocode(double lat, double lng) async {
    setState(() => _isFetchingLocation = true);
    final data = await _addressService.reverseGeocode(lat, lng);
    if (!mounted) return;

    setState(() {
      _addressLineController.text = data['addressLine'] ?? '';
      _cityController.text = data['city'] ?? '';
      _stateController.text = data['state'] ?? '';
      _postcodeController.text = data['postcode'] ?? '';
      _isFetchingLocation = false;
    });
    if ((data['addressLine'] ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Address lookup is unavailable. Enter the address details manually.'),
      ));
    }
  }

  Future<void> _searchAndAnimateMap() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _isFetchingLocation = true);

    final result = await _addressService.searchLocation(query);
    if (!mounted) return;

    if (result != null) {
      final lat = result['lat'] as double;
      final lng = result['lng'] as double;
      final target = LatLng(lat, lng);

      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newLatLngZoom(target, 17));

      _triggerReverseGeocode(lat, lng);
    } else {
      setState(() => _isFetchingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address not found in Malaysia. Please adjust pin manually.')),
      );
    }
  }

  Future<void> _saveAddress() async {
    if (_addressLineController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an address line')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final newAddress = await _addressService.addAddress(
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
      Navigator.pop(context, newAddress);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save address: $e'), backgroundColor: CustomerTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CustomerTheme.lightTheme,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('Add Service Location'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Stack(
          children: [
            // 1. Google Map View
            GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _initialPosition,
                zoom: 16.0,
              ),
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),

            // 2. Fixed Center Pin
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 35),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isFetchingLocation ? 'Locating...' : 'Set service location',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    const Icon(Icons.location_pin, size: 48, color: CustomerTheme.primary),
                  ],
                ),
              ),
            ),

            // 3. Top Search Box for Forward Geocoding
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchAndAnimateMap(),
                  decoration: InputDecoration(
                    hintText: 'Search area or building (e.g. Astrum Ampang)...',
                    prefixIcon: const Icon(Icons.search, color: CustomerTheme.primary),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, color: CustomerTheme.primary),
                      onPressed: _searchAndAnimateMap,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // 4. Bottom Form Card
            DraggableScrollableSheet(
              initialChildSize: 0.45,
              minChildSize: 0.22,
              maxChildSize: 0.85,
              builder: (ctx, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text('Address Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          if (_isFetchingLocation)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: CustomerTheme.primary),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Label Selector (Home, Office, Other)
                      Row(
                        children: ['Home', 'Office', 'Other'].map((label) {
                          final isSelected = _selectedLabel == label;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: isSelected,
                              selectedColor: CustomerTheme.primarySurface,
                              labelStyle: TextStyle(
                                color: isSelected ? CustomerTheme.primary : CustomerTheme.textPrimary,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              side: BorderSide(
                                color: isSelected ? CustomerTheme.primary : CustomerTheme.borderColor,
                              ),
                              onSelected: (_) => setState(() => _selectedLabel = label),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _addressLineController,
                        decoration: const InputDecoration(labelText: 'Address Line / Unit No.'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _cityController,
                              decoration: const InputDecoration(labelText: 'City'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _postcodeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Postcode'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _stateController,
                        decoration: const InputDecoration(labelText: 'State'),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: CustomerTheme.primary,
                        title: const Text('Set as default service address', style: TextStyle(fontSize: 14)),
                        value: _isDefault,
                        onChanged: (val) => setState(() => _isDefault = val),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveAddress,
                        child: _isSaving
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                            : const Text('Save & Select Address'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
