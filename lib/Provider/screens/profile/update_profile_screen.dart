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

  static const _primaryColor = Color(0xFF1E3A8A);

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
      _showError('Failed to load profile: $e');
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
      _showError('Failed to pick image: $e');
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_pickedImageBytes != null || _existingPhotoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.red)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Profile updated successfully'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Save failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadingPhoto = false;
        });
      }
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

  String? _validateRequired(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    return null;
  }

  String? _validateYears(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null) return 'Please enter a valid number';
    if (n < 0) return 'Cannot be negative';
    if (n > 80) return 'Value is too large';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Update Profile'),
        backgroundColor: _primaryColor,
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
                Center(child: _buildAvatar()),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _saving ? null : _showImageSourceSheet,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Change Photo'),
                    style: TextButton.styleFrom(
                      foregroundColor: _primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _label('Full Name'),
                TextFormField(
                  controller: _fullName,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: (v) => _validateRequired(v, 'Full name'),
                  decoration: _inputDecoration(
                    hint: 'Your full name',
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 16),

                _label('Phone Number'),
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

                _label('Business Name'),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: (v) =>
                      _validateRequired(v, 'Business name'),
                  decoration: _inputDecoration(
                    hint: 'e.g. ABC Services',
                    icon: Icons.storefront_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                _label('Bio'),
                TextFormField(
                  controller: _bio,
                  maxLines: 3,
                  enabled: !_saving,
                  decoration: _inputDecoration(
                    hint: 'Tell customers about your services...',
                    icon: Icons.description_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                _label('Years of Experience'),
                TextFormField(
                  controller: _years,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: _validateYears,
                  decoration: _inputDecoration(
                    hint: 'e.g. 5',
                    icon: Icons.timeline_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                _label('City'),
                TextFormField(
                  controller: _city,
                  textInputAction: TextInputAction.done,
                  enabled: !_saving,
                  onFieldSubmitted: (_) => _save(),
                  decoration: _inputDecoration(
                    hint: 'e.g. Kuala Lumpur',
                    icon: Icons.location_city_outlined,
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
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
                      _uploadingPhoto
                          ? 'Uploading photo...'
                          : 'Save Changes',
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
    } else if (_existingPhotoUrl != null &&
        _existingPhotoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_existingPhotoUrl!);
    }

    return Stack(
      children: [
        CircleAvatar(
          radius: 56,
          backgroundColor: const Color(0xFFDBEAFE),
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
            _fullName.text.isNotEmpty
                ? _fullName.text[0].toUpperCase()
                : 'U',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          )
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: _primaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white, size: 18),
              onPressed: _saving ? null : _showImageSourceSheet,
              tooltip: 'Edit photo',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600),
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