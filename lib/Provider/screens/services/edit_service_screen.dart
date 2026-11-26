import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final _client = Supabase.instance.client;

  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _duration = TextEditingController();

  String _pricing = 'Fixed';
  String? _categoryId;
  List<Map<String, dynamic>> _categories = [];

  bool _loading = true;
  bool _saving = false;

  // 🎨 Unified Orange + White theme
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
      final lang = Localizations.localeOf(context).languageCode;
      _showError(lang == 'zh'
          ? '加载失败：$e'
          : (lang == 'ms' ? 'Gagal memuatkan: $e' : 'Failed to load: $e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final lang = Localizations.localeOf(context).languageCode;

    if (_formKey.currentState?.validate() != true) return;
    if (_categoryId == null) {
      _showError(lang == 'zh'
          ? '请选择类别'
          : (lang == 'ms' ? 'Sila pilih kategori' : 'Please select a category'));
      return;
    }

    setState(() => _saving = true);

    try {
      final pid = await _service.getProviderId();
      if (pid == null) {
        throw Exception(
          lang == 'zh'
              ? '找不到服务商资料，请先完善您的资料。'
              : (lang == 'ms'
              ? 'Profil penyedia tidak dijumpai. Sila lengkapkan profil anda terlebih dahulu.'
              : 'Provider profile not found. Please complete your profile first.'),
        );
      }

      // 👇 核心新增：查重校验逻辑
      final serviceName = _title.text.trim();

      // 去数据库查同名且 is_active = true 的服务
      final existing = await _client
          .from('services')
          .select('service_id')
          .eq('provider_id', pid)
          .eq('service_name', serviceName)
          .eq('is_active', true)
          .maybeSingle();

      if (existing != null) {
        // 如果是新增，且查到了同名的
        if (!_isEditing) {
          _showError(lang == 'zh'
              ? '您已经有一个名为“$serviceName”的活跃服务。'
              : (lang == 'ms'
              ? 'Anda sudah mempunyai perkhidmatan aktif bernama "$serviceName".'
              : 'You already have an active service named "$serviceName".'));
          setState(() => _saving = false);
          return;
        }
        // 如果是编辑，查到的 ID 不是当前正在编辑的 ID，说明撞名了
        if (existing['service_id'] != widget.existing!['service_id']) {
          _showError(lang == 'zh'
              ? '另一个活跃服务已使用此名称。'
              : (lang == 'ms'
              ? 'Perkhidmatan aktif lain sudah menggunakan nama ini.'
              : 'Another active service already uses this name.'));
          setState(() => _saving = false);
          return;
        }
      }
      // 👆 查重逻辑结束

      final data = {
        'provider_id': pid,
        'category_id': _categoryId,
        'service_name': serviceName,
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
              Text(_isEditing
                  ? (lang == 'zh'
                  ? '服务已更新'
                  : (lang == 'ms' ? 'Perkhidmatan dikemas kini' : 'Service updated'))
                  : (lang == 'zh'
                  ? '服务已添加'
                  : (lang == 'ms' ? 'Perkhidmatan ditambah' : 'Service added'))),
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
      _showError(lang == 'zh'
          ? '保存失败：$e'
          : (lang == 'ms' ? 'Gagal menyimpan: $e' : 'Save failed: $e'));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ============ Validators ============

  String? _required(String? v, String labelEn, String labelZh, String labelMs) {
    final lang = Localizations.localeOf(context).languageCode;
    if (v == null || v.trim().isEmpty) {
      if (lang == 'zh') return '$labelZh不能为空';
      if (lang == 'ms') return '$labelMs diperlukan';
      return '$labelEn is required';
    }
    return null;
  }

  String? _validatePrice(String? v) {
    final lang = Localizations.localeOf(context).languageCode;
    if (v == null || v.trim().isEmpty) {
      return lang == 'zh'
          ? '价格为必填项'
          : (lang == 'ms' ? 'Harga diperlukan' : 'Price is required');
    }
    final n = double.tryParse(v.trim());
    if (n == null) {
      return lang == 'zh'
          ? '请输入有效的数字'
          : (lang == 'ms' ? 'Masukkan nombor yang sah' : 'Enter a valid number');
    }
    if (n < 0) {
      return lang == 'zh'
          ? '价格不能为负数'
          : (lang == 'ms' ? 'Harga tidak boleh negatif' : 'Price cannot be negative');
    }
    return null;
  }

  String? _validateDuration(String? v) {
    final lang = Localizations.localeOf(context).languageCode;
    if (v == null || v.trim().isEmpty) {
      return lang == 'zh'
          ? '时长为必填项'
          : (lang == 'ms' ? 'Tempoh diperlukan' : 'Duration is required');
    }
    final n = int.tryParse(v.trim());
    if (n == null) {
      return lang == 'zh'
          ? '请输入有效的数字'
          : (lang == 'ms' ? 'Masukkan nombor yang sah' : 'Enter a valid number');
    }
    if (n < 15) {
      return lang == 'zh'
          ? '最少 15 分钟'
          : (lang == 'ms' ? 'Minimum 15 minit' : 'Minimum 15 minutes');
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
          _isEditing
              ? (isZh ? '编辑服务' : (isMs ? 'Edit Perkhidmatan' : 'Edit Service'))
              : (isZh ? '添加服务' : (isMs ? 'Tambah Perkhidmatan' : 'Add Service')),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Category ----
                _label(isZh ? '类别' : (isMs ? 'Kategori' : 'Category')),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: _inputDecoration(
                    hint: isZh
                        ? '选择类别'
                        : (isMs ? 'Pilih kategori' : 'Select a category'),
                    icon: Icons.category_outlined,
                  ),
                  items: _categories
                      .map(
                        (c) => DropdownMenuItem<String>(
                      value: c['category_id'] as String,
                      child: Text(c['category_name'] ?? ''),
                    ),
                  )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _categoryId = v),
                  validator: (value) {
                    if (value == null) {
                      return isZh
                          ? '请选择类别'
                          : (isMs ? 'Sila pilih kategori' : 'Please select a category');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ---- Service Title ----
                _label(isZh ? '服务标题' : (isMs ? 'Tajuk Perkhidmatan' : 'Service Title')),
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: (value) => _required(
                    value,
                    'Service title',
                    '服务标题',
                    'Tajuk perkhidmatan',
                  ),
                  decoration: _inputDecoration(
                    hint: isZh
                        ? '例如：水管维修'
                        : (isMs ? 'cth. Pembaikan Paip' : 'e.g. Pipe Repair'),
                    icon: Icons.work_outline,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Description ----
                _label(isZh ? '描述' : (isMs ? 'Penerangan' : 'Description')),
                TextFormField(
                  controller: _desc,
                  maxLines: 3,
                  enabled: !_saving,
                  validator: (value) => _required(
                    value,
                    'Description',
                    '描述',
                    'Penerangan',
                  ),
                  decoration: _inputDecoration(
                    hint: isZh
                        ? '描述您的服务...'
                        : (isMs ? 'Terangkan perkhidmatan anda...' : 'Describe your service...'),
                    icon: Icons.description_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Pricing Type ----
                _label(isZh ? '定价类型' : (isMs ? 'Jenis Harga' : 'Pricing Type')),
                DropdownButtonFormField<String>(
                  initialValue: _pricing,
                  decoration: _inputDecoration(
                    hint: isZh
                        ? '选择定价类型'
                        : (isMs ? 'Pilih jenis harga' : 'Select pricing type'),
                    icon: Icons.attach_money,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'Fixed',
                      child: Text(isZh ? '固定' : (isMs ? 'Tetap' : 'Fixed')),
                    ),
                    DropdownMenuItem(
                      value: 'Hourly',
                      child: Text(isZh ? '按小时' : (isMs ? 'Setiap Jam' : 'Hourly')),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _pricing = v ?? 'Fixed'),
                ),
                const SizedBox(height: 16),

                // ---- Price ----
                _label(isZh
                    ? '价格金额 (RM)'
                    : (isMs ? 'Jumlah Harga (RM)' : 'Price Amount (RM)')),
                TextFormField(
                  controller: _price,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validatePrice,
                  decoration: _inputDecoration(
                    hint: isZh ? '例如：100' : (isMs ? 'cth. 100' : 'e.g. 100'),
                    icon: Icons.payments_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Duration ----
                _label(isZh
                    ? '预计时长 (分钟)'
                    : (isMs ? 'Anggaran Tempoh (minit)' : 'Estimated Duration (minutes)')),
                TextFormField(
                  controller: _duration,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  validator: _validateDuration,
                  decoration: _inputDecoration(
                    hint: isZh ? '例如：90' : (isMs ? 'cth. 90' : 'e.g. 90'),
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
                          ? (isZh ? '保存中...' : (isMs ? 'Menyimpan...' : 'Saving...'))
                          : (_isEditing
                          ? (isZh ? '保存更改' : (isMs ? 'Simpan Perubahan' : 'Save Changes'))
                          : (isZh ? '添加服务' : (isMs ? 'Tambah Perkhidmatan' : 'Add Service'))),
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