import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/profile_service.dart';

class EditCertificationScreen extends StatefulWidget {
  final Map<String, dynamic> certification;

  const EditCertificationScreen({
    super.key,
    required this.certification,
  });

  @override
  State<EditCertificationScreen> createState() =>
      _EditCertificationScreenState();
}

class _EditCertificationScreenState extends State<EditCertificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();

  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _expiry = TextEditingController();

  PlatformFile? _file;
  String? _existingFileUrl;
  bool _submitting = false;

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void initState() {
    super.initState();
    final c = widget.certification;
    _name.text = c['certification_name']?.toString() ?? '';
    _issuer.text = c['issuer']?.toString() ?? '';
    _expiry.text = c['expiry_date']?.toString() ?? '';
    _existingFileUrl = c['file_url']?.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (res != null && res.files.isNotEmpty) {
        setState(() => _file = res.files.first);
      }
    } catch (e) {
      _showError('Failed to pick file: $e');
    }
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _expiry.text =
      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

    final id = widget.certification['certification_id']?.toString();
    if (id == null || id.isEmpty) {
      _showError('Missing certification ID');
      return;
    }

    setState(() => _submitting = true);

    try {
      String? fileUrl;
      if (_file != null && _file!.bytes != null) {
        fileUrl = await _service.uploadFile(
          'certifications',
          '${DateTime.now().millisecondsSinceEpoch}_${_file!.name}',
          _file!.bytes!,
        );
      }

      await _service.updateCertification(id, {
        'certification_name': _name.text.trim(),
        'issuer': _issuer.text.trim(),
        'expiry_date': _expiry.text.isEmpty ? null : _expiry.text.trim(),
        'file_url': fileUrl ?? _existingFileUrl,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Certification updated'),
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
      _showError('Update failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
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

  String? _required(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Edit Certification'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Certification Name'),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                  validator: (v) => _required(v, 'Certification name'),
                  decoration: _inputDecoration(
                    hint: 'e.g. First Aid Certificate',
                    icon: Icons.workspace_premium_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                _label('Issuer'),
                TextFormField(
                  controller: _issuer,
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                  validator: (v) => _required(v, 'Issuer'),
                  decoration: _inputDecoration(
                    hint: 'e.g. Red Crescent',
                    icon: Icons.business_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                _label('Expiry Date'),
                TextFormField(
                  controller: _expiry,
                  readOnly: true,
                  enabled: !_submitting,
                  onTap: _pickExpiryDate,
                  decoration: _inputDecoration(
                    hint: 'Tap to select date',
                    icon: Icons.calendar_today_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                _label('Certificate File (Optional)'),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickFile,
                  icon: Icon(
                    _file == null
                        ? Icons.upload_file_outlined
                        : Icons.check_circle_outline,
                    color: _primaryColor,
                  ),
                  label: Text(
                    _file == null
                        ? (_existingFileUrl != null
                        ? 'Keep existing file'
                        : 'Choose File')
                        : _file!.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _primaryColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: _primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _save,
                    icon: _submitting
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.save),
                    label: Text(
                      _submitting ? 'Saving...' : 'Save Changes',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
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
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }
}