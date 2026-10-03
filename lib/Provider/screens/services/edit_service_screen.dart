import 'package:flutter/material.dart';
import '../../services/service_service.dart';

class EditServiceScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const EditServiceScreen({super.key, this.existing});

  @override
  State<EditServiceScreen> createState() => _EditServiceScreenState();
}

class _EditServiceScreenState extends State<EditServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ServiceService();

  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _duration = TextEditingController();

  String _pricing = 'Fixed';
  String? _categoryId;
  List<Map<String, dynamic>> _categories = [];

  bool _loading = true;
  bool _saving = false;

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _categories = await _service.getCategories();

      if (_isEditing) {
        final e = widget.existing!;
        _title.text = e['service_name']?.toString() ?? '';
        _desc.text = e['description']?.toString() ?? '';
        _price.text = e['base_price']?.toString() ?? '';
        _duration.text = e['estimated_duration']?.toString() ?? '';
        _pricing = e['pricing_type']?.toString() ?? 'Fixed';
        _categoryId = e['category_id']?.toString();
      } else if (_categories.isNotEmpty) {
        _categoryId = _categories.first['category_id']?.toString();
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
    if (_categoryId == null) {
      _showError('Please select a category');
      return;
    }

    setState(() => _saving = true);

    try {
      final pid = await _service.getProviderId();
      if (pid == null) {
        throw Exception(
            'Provider profile not found. Please complete your profile first.');
      }

      final data = {
        'provider_id': pid,
        'category_id': _categoryId,
        'service_name': _title.text.trim(),
        'description': _desc.text.trim(),
        'pricing_type': _pricing,
        'base_price': double.tryParse(_price.text.trim()) ?? 0,
        'estimated_duration': int.tryParse(_duration.text.trim()) ?? 60,
      };

      if (_isEditing) {
        await _service.updateService(widget.existing!['service_id'], data);
      } else {
        await _service.addService(data);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(_isEditing ? 'Service updated' : 'Service added'),
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

  String? _required(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    return null;
  }

  String? _validatePrice(String? v) {
    if (v == null || v.trim().isEmpty) return 'Price is required';
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 0) return 'Price cannot be negative';
    return null;
  }

  String? _validateDuration(String? v) {
    if (v == null || v.trim().isEmpty) return 'Duration is required';
    final n = int.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 15) return 'Minimum 15 minutes';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Service' : 'Add Service'),
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
                // ---- Category ----
                _label('Category'),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: _inputDecoration(
                    hint: 'Select a category',
                    icon: Icons.category_outlined,
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem<String>(
                    value: c['category_id'] as String,
                    child: Text(c['category_name'] ?? ''),
                  ))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _categoryId = v),
                  validator: (v) =>
                  v == null ? 'Please select a category' : null,
                ),
                const SizedBox(height: 16),

                // ---- Service Title ----
                _label('Service Title'),
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: (v) => _required(v, 'Service title'),
                  decoration: _inputDecoration(
                    hint: 'e.g. Pipe Repair',
                    icon: Icons.work_outline,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Description ----
                _label('Description'),
                TextFormField(
                  controller: _desc,
                  maxLines: 3,
                  enabled: !_saving,
                  validator: (v) => _required(v, 'Description'),
                  decoration: _inputDecoration(
                    hint: 'Describe your service...',
                    icon: Icons.description_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Pricing Type ----
                _label('Pricing Type'),
                DropdownButtonFormField<String>(
                  initialValue: _pricing,
                  decoration: _inputDecoration(
                    hint: 'Select pricing type',
                    icon: Icons.attach_money,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'Fixed', child: Text('Fixed')),
                    DropdownMenuItem(
                        value: 'Hourly', child: Text('Hourly')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _pricing = v ?? 'Fixed'),
                ),
                const SizedBox(height: 16),

                // ---- Price ----
                _label('Price Amount (RM)'),
                TextFormField(
                  controller: _price,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  validator: _validatePrice,
                  decoration: _inputDecoration(
                    hint: 'e.g. 100',
                    icon: Icons.payments_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Duration ----
                _label('Estimated Duration (minutes)'),
                TextFormField(
                  controller: _duration,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  validator: _validateDuration,
                  decoration: _inputDecoration(
                    hint: 'e.g. 90',
                    icon: Icons.timer_outlined,
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
                        : Icon(_isEditing ? Icons.save : Icons.add),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : (_isEditing
                          ? 'Save Changes'
                          : 'Add Service'),
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
    );
  }
}