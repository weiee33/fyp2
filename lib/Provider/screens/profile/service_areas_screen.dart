import 'package:flutter/material.dart';
import '../../services/profile_service.dart';

class ServiceAreasScreen extends StatefulWidget {
  const ServiceAreasScreen({super.key});
  @override
  State<ServiceAreasScreen> createState() => _ServiceAreasScreenState();
}

class _ServiceAreasScreenState extends State<ServiceAreasScreen> {
  final _service = ProfileService();
  String _region = 'Klang Valley';
  final _city = TextEditingController();
  final _radius = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _service.getMyProfile();
    if (p != null) {
      _region = p['region'] ?? 'Klang Valley';
      _city.text = p['city'] ?? '';
      _radius.text = (p['service_radius_km'] ?? '').toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await _service.updateProfile({
      'region': _region,
      'city': _city.text,
      'service_radius_km': int.tryParse(_radius.text) ?? 10,
    });
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Service Areas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Align(
                      alignment: Alignment.centerLeft, child: Text('Region')),
                  DropdownButtonFormField<String>(
                    value: _region,
                    items: const [
                      'Klang Valley',
                      'Penang',
                      'Johor Bahru',
                      'Other'
                    ]
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => _region = v!),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                      alignment: Alignment.centerLeft, child: Text('City')),
                  TextField(controller: _city),
                  const SizedBox(height: 12),
                  const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Service Radius (km)')),
                  TextField(
                      controller: _radius,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ),
    );
  }
}