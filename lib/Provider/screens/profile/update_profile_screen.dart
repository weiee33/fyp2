import 'package:fyp2/shared/localization/app_language.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/profile_service.dart';

class UpdateProfileScreen extends StatefulWidget {
  const UpdateProfileScreen({super.key});

  @override
  State<UpdateProfileScreen> createState() => _UpdateProfileScreenState();
}

class _UpdateProfileScreenState extends State<UpdateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();
  final _picker = ImagePicker();

  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _years = TextEditingController();
  final _city = TextEditingController();

  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;
  String? _existingPhotoUrl;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  // 🎨 Unified Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _name.dispose();
    _bio.dispose();
    _years.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _service.getMyProfile();
      if (p != null) {
        _fullName.text = p['full_name'] ?? '';
        _phone.text = p['phone'] ?? '';
        _name.text = p['business_name'] ?? '';
        _bio.text = p['bio'] ?? '';
        _years.text = (p['years_experience'] ?? 0).toString();
        _city.text = p['city'] ?? '';
        _existingPhotoUrl = p['profile_photo_url'];
      }
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: 'Error',
        message: "Failed to load profile: $e",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();

      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageExt = ext;
      });
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: 'Error',
        message: "Failed to pick image: $e",
        isError: true,
      );
    }
  }

  void _showImageSourceSheet() {
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: _primaryOrange),
              title: Text(isZh ? '从相册选择' : (isMs ? 'Pilih dari Galeri' : 'Choose from Gallery')),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: _primaryOrange),
              title: Text(isZh ? '拍照' : (isMs ? 'Ambil Gambar' : 'Take a Photo')),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_pickedImageBytes != null || _existingPhotoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  isZh ? '移除照片' : (isMs ? 'Buang Gambar' : 'Remove Photo'),
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _pickedImageBytes = null;
                    _existingPhotoUrl = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _saving = true);

    try {
      String? photoUrl;
      if (_pickedImageBytes != null && _pickedImageExt != null) {
        setState(() => _uploadingPhoto = true);
        photoUrl = await _service.uploadAvatar(
          _pickedImageBytes!,
          _pickedImageExt!,
        );
        setState(() => _uploadingPhoto = false);
      } else if (_existingPhotoUrl != null) {
        photoUrl = _existingPhotoUrl;
      }

      await _service.updateProfile({
        'full_name': _fullName.text.trim(),
        'phone': _phone.text.trim(),
        'profile_photo_url': photoUrl,
        'business_name': _name.text.trim(),
        'bio': _bio.text.trim(),
        'years_experience': int.tryParse(_years.text.trim()) ?? 0,
        'city': _city.text.trim(),
      });

      if (!mounted) return;

      _showAppDialog(
        title: 'Success',
        message: 'Profile updated successfully.',
        isError: false,
      );

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: 'Error',
        message: "Save failed: $e",
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadingPhoto = false;
        });
      }
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

  String? _validateRequired(String? v, String labelEn, String labelZh, String labelMs) {
    final lang = Localizations.localeOf(context).languageCode;
    if (v == null || v.trim().isEmpty) {
      if (lang == 'zh') return '$labelZh不能为空';
      if (lang == 'ms') return '$labelMs diperlukan';
      return '$labelEn is required';
    }
    return null;
  }

  String? _validateYears(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    final lang = Localizations.localeOf(context).languageCode;
    if (n == null) {
      return lang == 'zh' ? '请输入有效的数字' : (lang == 'ms' ? 'Masukkan nombor yang sah' : 'Please enter a valid number');
    }
    if (n < 0) {
      return lang == 'zh' ? '不能为负数' : (lang == 'ms' ? 'Tidak boleh negatif' : 'Cannot be negative');
    }
    if (n > 80) {
      return lang == 'zh' ? '数值太大' : (lang == 'ms' ? 'Nilai terlalu besar' : 'Value is too large');
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
        // 👇 强制 AppBar 标题为白色
        title: Text(
          isZh ? '更新个人资料' : (isMs ? 'Kemas Kini Profil' : 'Update Profile'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
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
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _buildAvatar()),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _saving ? null : _showImageSourceSheet,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(isZh ? '更改照片' : (isMs ? 'Tukar Gambar' : 'Change Photo')),
                    style: TextButton.styleFrom(
                      foregroundColor: _primaryOrange,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _label(isZh ? '全名' : (isMs ? 'Nama Penuh' : 'Full Name')),
                TextFormField(
                  controller: _fullName,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: (value) => _validateRequired(
                      value,
                      'Full name',
                      '全名',
                      'Nama penuh'
                  ),
                  decoration: _inputDecoration(
                    hint: isZh ? '您的全名' : (isMs ? 'Nama penuh anda' : 'Your full name'),
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 16),

                _label(isZh ? '电话号码' : (isMs ? 'Nombor Telefon' : 'Phone Number')),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  decoration: _inputDecoration(
                    hint: '+60 12-345 6789',
                    icon: Icons.phone_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                _label(isZh ? '业务名称' : (isMs ? 'Nama Perniagaan' : 'Business Name')),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: (value) => _validateRequired(
                      value,
                      'Business name',
                      '业务名称',
                      'Nama perniagaan'
                  ),
                  decoration: _inputDecoration(
                    hint: isZh ? '例如：ABC Services' : (isMs ? 'cth. ABC Services' : 'e.g. ABC Services'),
                    icon: Icons.storefront_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                _label(isZh ? '个人简介' : (isMs ? 'Bio' : 'Bio')),
                TextFormField(
                  controller: _bio,
                  maxLines: 3,
                  enabled: !_saving,
                  decoration: _inputDecoration(
                    hint: isZh ? '向客户介绍您的服务...' : (isMs ? 'Beritahu pelanggan tentang perkhidmatan anda...' : 'Tell customers about your services...'),
                    icon: Icons.description_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                _label(isZh ? '工作经验（年）' : (isMs ? 'Pengalaman Kerja (tahun)' : 'Years of Experience')),
                TextFormField(
                  controller: _years,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: _validateYears,
                  decoration: _inputDecoration(
                    hint: isZh ? '例如：5' : (isMs ? 'cth. 5' : 'e.g. 5'),
                    icon: Icons.timeline_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                _label(isZh ? '城市' : (isMs ? 'Bandar' : 'City')),
                TextFormField(
                  controller: _city,
                  textInputAction: TextInputAction.done,
                  enabled: !_saving,
                  onFieldSubmitted: (_) => _save(),
                  decoration: _inputDecoration(
                    hint: isZh ? '例如：吉隆坡' : (isMs ? 'cth. Kuala Lumpur' : 'e.g. Kuala Lumpur'),
                    icon: Icons.location_city_outlined,
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _saving
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                        : Text(
                      isZh ? ( _uploadingPhoto ? '上传照片中...' : '保存更改' )
                          : (isMs ? ( _uploadingPhoto ? 'Memuat naik gambar...' : 'Simpan Perubahan' )
                          : ( _uploadingPhoto ? 'Uploading photo...' : 'Save Changes' )),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildAvatar() {
    ImageProvider? imageProvider;
    if (_pickedImageBytes != null) {
      imageProvider = MemoryImage(_pickedImageBytes!);
    } else if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_existingPhotoUrl!);
    }

    return Stack(
      children: [
        CircleAvatar(
          radius: 56,
          backgroundColor: _lightOrange,
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
            _fullName.text.isNotEmpty
                ? _fullName.text[0].toUpperCase()
                : 'U',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: _primaryOrange,
            ),
          )
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: _primaryOrange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white, size: 18),
              onPressed: _saving ? null : _showImageSourceSheet,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
            ),
          ),
        ),
      ],
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