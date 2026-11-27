import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/profile_service.dart';

class EditCertificationScreen extends StatefulWidget {
  final Map<String, dynamic> certification;

  const EditCertificationScreen({super.key, required this.certification});

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

  // 🎨 Unified Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);

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
      _showAppDialog(title: 'Error', message: 'Failed to pick file: $e', isError: true);
    }
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryOrange,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
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
      _showAppDialog(title: 'Error', message: 'Missing certification ID', isError: true);
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

      _showAppDialog(
        title: 'Success',
        message: 'Certification updated.',
        isError: false,
      );

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(title: 'Error', message: 'Update failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ============= Pop-up Box 弹窗 =============
  void _showAppDialog({required String title, required String message, required bool isError}) {
    showDialog(
      context: context,
      builder: (ctx) {
        final lang = Localizations.localeOf(context).languageCode;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isError ? Colors.red.shade50 : Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: isError ? Colors.red.shade600 : Colors.green.shade600,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      lang == 'zh' ? '知道了' : (lang == 'ms' ? 'OK' : 'OK'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _required(String? v, String label) {
    if (v == null || v.trim().isEmpty) {
      final lang = Localizations.localeOf(context).languageCode;
      if (lang == 'zh') return '$label不能为空';
      if (lang == 'ms') return '$label diperlukan';
      return '$label is required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isZh ? '编辑证书' : (isMs ? 'Edit Sijil' : 'Edit Certification'),
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white
          ),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label(isZh ? '证书名称' : (isMs ? 'Nama Sijil' : 'Certification Name')),
                          TextFormField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            enabled: !_submitting,
                            validator: (value) => _required(
                              value,
                              isZh ? '证书名称' : (isMs ? 'Nama Sijil' : 'Certification name'),
                            ),
                            decoration: _inputDecoration(
                              hint: isZh ? '例如：急救证书' : (isMs ? 'cth. Sijil Bantuan Awal' : 'e.g. First Aid Certificate'),
                              icon: Icons.workspace_premium_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label(isZh ? '颁发机构' : (isMs ? 'Pengeluar' : 'Issuer')),
                          TextFormField(
                            controller: _issuer,
                            textInputAction: TextInputAction.next,
                            enabled: !_submitting,
                            validator: (value) => _required(
                              value,
                              isZh ? '颁发机构' : (isMs ? 'Pengeluar' : 'Issuer'),
                            ),
                            decoration: _inputDecoration(
                              hint: isZh ? '例如：红十字会' : (isMs ? 'cth. Bulan Sabit Merah' : 'e.g. Red Crescent'),
                              icon: Icons.business_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label(isZh ? '到期日期' : (isMs ? 'Tarikh Luput' : 'Expiry Date')),
                          TextFormField(
                            controller: _expiry,
                            readOnly: true,
                            enabled: !_submitting,
                            onTap: _pickExpiryDate,
                            decoration: _inputDecoration(
                              hint: isZh ? '点击选择日期' : (isMs ? 'Ketik untuk pilih tarikh' : 'Tap to select date'),
                              icon: Icons.calendar_today_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _label(isZh ? '证书文件（可选）' : (isMs ? 'Fail Sijil (Pilihan)' : 'Certificate File (Optional)')),
                          OutlinedButton.icon(
                            onPressed: _submitting ? null : _pickFile,
                            icon: Icon(
                              _file == null
                                  ? Icons.upload_file_outlined
                                  : Icons.check_circle_outline,
                              color: _primaryOrange,
                            ),
                            label: Text(
                              _file == null
                                  ? (_existingFileUrl != null
                                  ? (isZh ? '保留现有文件' : (isMs ? 'Kekalkan fail sedia ada' : 'Keep existing file'))
                                  : (isZh ? '选择文件' : (isMs ? 'Pilih Fail' : 'Choose File')))
                                  : _file!.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _primaryOrange),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: _primaryOrange),
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
                                _submitting
                                    ? (isZh ? '保存中...' : (isMs ? 'Menyimpan...' : 'Saving...'))
                                    : (isZh ? '保存更改' : (isMs ? 'Simpan Perubahan' : 'Save Changes')),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryOrange,
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
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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