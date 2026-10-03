import 'package:flutter/material.dart';
import '../../services/profile_service.dart';

class ServiceAreasScreen extends StatefulWidget {
  const ServiceAreasScreen({super.key});

  @override
  State<ServiceAreasScreen> createState() => _ServiceAreasScreenState();
}

class _ServiceAreasScreenState extends State<ServiceAreasScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();

  String _region = 'Klang Valley';
  final _city = TextEditingController();
  final _radius = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  static const _regions = [
    'Klang Valley',
    'Penang',
    'Johor Bahru',
    'Ipoh',
    'Melaka',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _city.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _service.getMyProfile();
      if (p != null) {
        _region = p['region']?.toString() ?? 'Klang Valley';
        if (!_regions.contains(_region)) _region = 'Other';
        _city.text = p['city']?.toString() ?? '';
        _radius.text = p['service_radius_km']?.toString() ?? '10';
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _saving = true);

    try {
      await _service.updateProfile({
        'region': _region,
        'city': _city.text.trim(),
        'service_radius_km': int.tryParse(_radius.text.trim()) ?? 10,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Service areas saved'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ============ Validators ============
  String? _validateCity(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'City is required';
    if (value.length < 2) return 'City name is too short';
    return null;
  }

  String? _validateRadius(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Service radius is required';
    final n = int.tryParse(value);
    if (n == null) return 'Enter a valid number';
    if (n < 1) return 'Radius must be at least 1 km';
    if (n > 200) return 'Radius cannot exceed 200 km';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Service Areas'),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Header Card ----
                Card(
                  elevation: 2,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: _borderOrange),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _lightOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: _primaryOrange,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Where do you work?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _primaryOrange,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Set your region, city, and travel radius',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Region ----
                _label('Region'),
                DropdownButtonFormField<String>(
                  initialValue: _region,
                  decoration: _inputDecoration(
                    hint: 'Select a region',
                    icon: Icons.map_outlined,
                  ),
                  items: _regions
                      .map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(r),
                  ))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _region = v ?? 'Other'),
                ),
                const SizedBox(height: 16),

                // ---- City ----
                _label('City'),
                TextFormField(
                  controller: _city,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: _validateCity,
                  decoration: _inputDecoration(
                    hint: 'e.g. Kuala Lumpur',
                    icon: Icons.location_city_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Radius ----
                _label('Service Radius (km)'),
                TextFormField(
                  controller: _radius,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  enabled: !_saving,
                  validator: _validateRadius,
                  onFieldSubmitted: (_) => _save(),
                  decoration: _inputDecoration(
                    hint: 'e.g. 10',
                    icon: Icons.radar_outlined,
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    'How far are you willing to travel from your city?',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ---- Save Button ----
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? 'Saving...' : 'Save',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    ),
  );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}