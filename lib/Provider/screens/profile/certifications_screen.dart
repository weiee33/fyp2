import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/profile_service.dart';
import 'edit_certification_screen.dart';

class CertificationsScreen extends StatefulWidget {
  const CertificationsScreen({super.key});

  @override
  State<CertificationsScreen> createState() => _CertificationsScreenState();
}

class _CertificationsScreenState extends State<CertificationsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();

  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _expiry = TextEditingController();

  PlatformFile? _file;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _submitting = false;

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final items = await _service.getCertifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Failed to load certifications: $e');
    }
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

  Future<void> _add() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

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

      await _service.addCertification({
        'certification_name': _name.text.trim(),
        'issuer': _issuer.text.trim(),
        'expiry_date': _expiry.text.isEmpty ? null : _expiry.text.trim(),
        'file_url': fileUrl,
      });

      _name.clear();
      _issuer.clear();
      _expiry.clear();
      setState(() => _file = null);

      if (!mounted) return;
      _showSuccess('Certification added');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to add: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Certification'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteCertification(id);
      if (!mounted) return;
      _showSuccess('Deleted');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Delete failed: $e');
    }
  }

  Future<void> _openEdit(Map<String, dynamic> item) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCertificationScreen(certification: item),
      ),
    );
    if (updated == true) {
      await _load();
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

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(msg),
          ],
        ),
        backgroundColor: Colors.green.shade600,
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
        title: const Text('Certifications'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Add Form ----
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Add New Certification',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _label('Certification Name'),
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        enabled: !_submitting,
                        validator: (v) =>
                            _required(v, 'Certification name'),
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
                          _file == null ? 'Choose File' : _file!.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _primaryColor),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: _primaryColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _add,
                          icon: _submitting
                              ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(Icons.add),
                          label: Text(
                            _submitting ? 'Adding...' : 'Add Certification',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
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
            const SizedBox(height: 24),

            // ---- List ----
            const Text(
              'My Certifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.folder_open_outlined,
                          size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No certifications yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._items.map((c) {
                final id = c['certification_id']?.toString() ?? '';
                final name = c['certification_name'] ?? '-';
                final issuer = c['issuer'] ?? '-';
                final expiry = c['expiry_date']?.toString();
                final fileUrl = c['file_url']?.toString();

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFDBEAFE),
                      child: Icon(Icons.workspace_premium,
                          color: _primaryColor),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(issuer),
                        if (expiry != null && expiry.isNotEmpty)
                          Text(
                            'Expires: $expiry',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (fileUrl != null && fileUrl.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.file_present,
                                color: _primaryColor),
                            tooltip: 'View File',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('File URL: $fileUrl')),
                              );
                            },
                          ),
                        // ---- Edit button -> go to new page ----
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: _primaryColor),
                          tooltip: 'Edit',
                          onPressed: () => _openEdit(c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          tooltip: 'Delete',
                          onPressed:
                          id.isEmpty ? null : () => _delete(id),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
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