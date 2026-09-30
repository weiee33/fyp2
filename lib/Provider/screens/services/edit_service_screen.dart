import 'package:flutter/material.dart';
import '../../services/service_service.dart';

class EditServiceScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const EditServiceScreen({super.key, this.existing});
  @override
  State<EditServiceScreen> createState() => _EditServiceScreenState();
}

class _EditServiceScreenState extends State<EditServiceScreen> {
  final _service = ServiceService();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _duration = TextEditingController();
  String _pricing = 'Fixed';
  String? _categoryId;
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _categories = await _service.getCategories();
    if (widget.existing != null) {
      _title.text = widget.existing!['service_name'] ?? '';
      _desc.text = widget.existing!['description'] ?? '';
      _price.text = widget.existing!['base_price'].toString();
      _duration.text = widget.existing!['estimated_duration'].toString();
      _pricing = widget.existing!['pricing_type'] ?? 'Fixed';
      _categoryId = widget.existing!['category_id'];
    } else if (_categories.isNotEmpty) {
      _categoryId = _categories.first['category_id'];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final pid = await _service.getProviderId();
    if (pid == null) return;
    final data = {
      'provider_id': pid,
      'category_id': _categoryId,
      'service_name': _title.text,
      'description': _desc.text,
      'pricing_type': _pricing,
      'base_price': double.tryParse(_price.text) ?? 0,
      'estimated_duration': int.tryParse(_duration.text) ?? 60,
    };
    if (widget.existing == null) {
      await _service.addService(data);
    } else {
      await _service.updateService(widget.existing!['service_id'], data);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'Add Service' : 'Edit Service')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  const Text('Category'),
                  DropdownButtonFormField<String>(
                    value: _categoryId,
                    items: _categories
                        .map((c) => DropdownMenuItem<String>(
                              value: c['category_id'] as String,
                              child: Text(c['category_name'] ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('Service Title'),
                  TextField(controller: _title),
                  const SizedBox(height: 12),
                  const Text('Description'),
                  TextField(controller: _desc, maxLines: 3),
                  const SizedBox(height: 12),
                  const Text('Pricing Type'),
                  DropdownButtonFormField<String>(
                    value: _pricing,
                    items: const [
                      DropdownMenuItem(value: 'Fixed', child: Text('Fixed')),
                      DropdownMenuItem(value: 'Hourly', child: Text('Hourly')),
                    ],
                    onChanged: (v) => setState(() => _pricing = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Price Amount RM'),
                  TextField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true)),
                  const SizedBox(height: 12),
                  const Text('Estimated Duration (minutes)'),
                  TextField(
                      controller: _duration,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 24),
                  ElevatedButton(
                      onPressed: _save,
                      child: Text(widget.existing == null
                          ? 'Add Service'
                          : 'Save Changes')),
                ],
              ),
            ),
    );
  }
}