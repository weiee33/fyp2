import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

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
      final lang = Localizations.localeOf(context).languageCode;
      _showAppDialog(
        title: lang == 'zh' ? '错误' : (lang == 'ms' ? 'Ralat' : 'Error'),
        message: lang == 'zh' ? '加载证书失败：$e' : (lang == 'ms' ? 'Gagal memuatkan sijil: $e' : 'Failed to load certifications: $e'),
        isError: true,
      );
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
        final file = res.files.first;
        setState(() => _file = file);

        final nameParts = file.name.split('.').first.split('_');
        if (nameParts.isNotEmpty) {
          _name.text = nameParts[0];
          if (nameParts.length > 1) _issuer.text = nameParts[1];
          if (nameParts.length > 2) {
            final lastPart = nameParts.last;
            final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
            if (dateRegex.hasMatch(lastPart)) _expiry.text = lastPart;
          }
        }
      }
    } catch (e) {
      final lang = Localizations.localeOf(context).languageCode;
      _showAppDialog(
        title: lang == 'zh' ? '错误' : (lang == 'ms' ? 'Ralat' : 'Error'),
        message: lang == 'zh' ? '选择文件失败：$e' : (lang == 'ms' ? 'Gagal memilih fail: $e' : 'Failed to pick file: $e'),
        isError: true,
      );
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
      final lang = Localizations.localeOf(context).languageCode;
      _showAppDialog(
        title: lang == 'zh' ? '成功' : (lang == 'ms' ? 'Berjaya' : 'Success'),
        message: lang == 'zh' ? '证书已添加' : (lang == 'ms' ? 'Sijil ditambah' : 'Certification added'),
        isError: false,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final lang = Localizations.localeOf(context).languageCode;
      _showAppDialog(
        title: lang == 'zh' ? '错误' : (lang == 'ms' ? 'Ralat' : 'Error'),
        message: lang == 'zh' ? '添加失败：$e' : (lang == 'ms' ? 'Gagal menambah: $e' : 'Failed to add: $e'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete(String id) async {
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isZh ? '删除证书' : (isMs ? 'Padam Sijil' : 'Delete Certification'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          isZh ? '您确定吗？' : (isMs ? 'Adakah anda pasti?' : 'Are you sure?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
            child: Text(isZh ? '取消' : (isMs ? 'Batal' : 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(isZh ? '删除' : (isMs ? 'Padam' : 'Delete')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteCertification(id);
      if (!mounted) return;
      _showAppDialog(
        title: isZh ? '已删除' : (isMs ? 'Dipadam' : 'Deleted'),
        message: isZh ? '证书已删除。' : (isMs ? 'Sijil dipadamkan.' : 'Certification deleted.'),
        isError: false,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: isZh ? '错误' : (isMs ? 'Ralat' : 'Error'),
        message: isZh ? '删除失败：$e' : (isMs ? 'Gagal memadam: $e' : 'Delete failed: $e'),
        isError: true,
      );
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
          isZh ? '证书' : (isMs ? 'Sijil' : 'Certifications'),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(color: _primaryOrange),
      )
          : SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryOrange,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Add Form ----
              Card(
                elevation: 2,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _borderOrange),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          isZh ? '添加新证书' : (isMs ? 'Tambah Sijil Baharu' : 'Add New Certification'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _primaryOrange,
                          ),
                        ),
                        const SizedBox(height: 16),
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
                                ? (isZh ? '选择文件' : (isMs ? 'Pilih Fail' : 'Choose File'))
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
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _add,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : Text(
                              isZh ? '添加证书' : (isMs ? 'Tambah Sijil' : 'Add Certification'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
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
              Text(
                isZh ? '我的证书' : (isMs ? 'Sijil Saya' : 'My Certifications'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _primaryOrange,
                ),
              ),
              const SizedBox(height: 12),

              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.folder_open_outlined,
                          size: 56,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isZh ? '暂无证书' : (isMs ? 'Tiada sijil lagi' : 'No certifications yet'),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
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

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Slidable(
                        key: ValueKey(id),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          extentRatio: 0.5,
                          children: [
                            if (fileUrl != null && fileUrl.isNotEmpty)
                              SlidableAction(
                                borderRadius: BorderRadius.circular(12),
                                onPressed: (_) {
                                  _showAppDialog(
                                    title: 'File URL',
                                    message: fileUrl,
                                    isError: false,
                                  );
                                },
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                icon: Icons.file_present,
                                label: isZh ? '文件' : (isMs ? 'Fail' : 'File'),
                              ),
                            SlidableAction(
                              borderRadius: BorderRadius.circular(12),
                              onPressed: (_) => _openEdit(c),
                              backgroundColor: _primaryOrange,
                              foregroundColor: Colors.white,
                              icon: Icons.edit_outlined,
                              label: isZh ? '编辑' : (isMs ? 'Edit' : 'Edit'),
                            ),
                            SlidableAction(
                              borderRadius: BorderRadius.circular(12),
                              onPressed: (_) => _delete(id),
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              icon: Icons.delete_outline,
                              label: isZh ? '删除' : (isMs ? 'Padam' : 'Delete'),
                            ),
                          ],
                        ),
                        child: Card(
                          elevation: 1,
                          color: Colors.white,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: _borderOrange),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _lightOrange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.workspace_premium,
                                    color: _primaryOrange,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        issuer,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      if (expiry != null && expiry.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          isZh ? '到期: $expiry' : (isMs ? 'Luput: $expiry' : 'Expires: $expiry'),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
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