import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_profile_service.dart';
import '../../services/customer_image_service.dart';

class CustomerEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? profileData;

  const CustomerEditProfileScreen({super.key, this.profileData});

  @override
  State<CustomerEditProfileScreen> createState() =>
      _CustomerEditProfileScreenState();
}

class _CustomerEditProfileScreenState extends State<CustomerEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = CustomerProfileService();
  final _picker = ImagePicker();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;
  String? _existingPhotoUrl;
  String? _uploadedPhotoUrl;

  bool _isSaving = false;

  // Preference Tags mapping
  List<String> _availablePreferences = [];
  String? _preferencesError;
  final Set<String> _selectedPreferences = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profileData?['full_name'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.profileData?['phone'] ?? '',
    );
    _existingPhotoUrl = widget.profileData?['profile_photo_url'];

    // Load existing preferences from DB array
    if (widget.profileData?['service_preferences'] != null) {
      final List<dynamic> prefs = widget.profileData!['service_preferences'];
      _selectedPreferences.addAll(prefs.map((e) => e.toString()));
    }
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final options = await _profileService.getPreferenceOptions();
      if (mounted)
        setState(() {
          _availablePreferences = {
            ...options,
            ..._selectedPreferences,
          }.toList();
          _preferencesError = null;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _availablePreferences = _selectedPreferences.toList();
          _preferencesError =
              'Could not load service categories. Your saved preferences are kept.';
        });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      CustomerImageService.validate(bytes, ext);
      if (!mounted) return;
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageExt = ext;
        _uploadedPhotoUrl = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
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
              leading: const Icon(
                Icons.photo_library_rounded,
                color: CustomerTheme.primary,
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: CustomerTheme.primary,
              ),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isSaving = true);

    try {
      // Upload new image if selected
      if (_pickedImageBytes != null &&
          _pickedImageExt != null &&
          _uploadedPhotoUrl == null) {
        _uploadedPhotoUrl = await _profileService.uploadAvatar(
          _pickedImageBytes!,
          _pickedImageExt!,
        );
      }

      await _profileService.updateProfile(
        fullName: _nameController.text,
        phone: _phoneController.text,
        photoUrl: _uploadedPhotoUrl,
        preferences: _selectedPreferences.toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: CustomerTheme.success,
        ),
      );
      Navigator.pop(context, true); // Return true to trigger reload
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: $e'),
          backgroundColor: CustomerTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CustomerTheme.background,
      appBar: AppBar(title: const Text('Edit Profile')),
      body: _isSaving
          ? const Center(
              child: CircularProgressIndicator(color: CustomerTheme.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              physics: const BouncingScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar Section
                    Center(
                      child: Stack(
                        children: [
                          Hero(
                            tag: 'avatar_hero',
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: CustomerTheme.primarySurface,
                              backgroundImage: _pickedImageBytes != null
                                  ? MemoryImage(_pickedImageBytes!)
                                        as ImageProvider
                                  : (_existingPhotoUrl != null &&
                                            _existingPhotoUrl!.isNotEmpty
                                        ? NetworkImage(_existingPhotoUrl!)
                                        : null),
                              child:
                                  (_pickedImageBytes == null &&
                                      (_existingPhotoUrl == null ||
                                          _existingPhotoUrl!.isEmpty))
                                  ? const Icon(
                                      Icons.person,
                                      size: 50,
                                      color: CustomerTheme.primary,
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _showImageSourceSheet,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: CustomerTheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Personal Details
                    const Text(
                      'Full Name',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      maxLength: 100,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Name is required'
                          : null,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Phone Number',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      validator: (v) =>
                          v == null ||
                              !RegExp(
                                r'^\+?[0-9][0-9 -]{6,19}$',
                              ).hasMatch(v.trim())
                          ? 'Enter a valid phone number'
                          : null,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Preference Tags (Use Case: Manage Preference Tags)
                    const Text(
                      'Service Preferences',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select services you frequently need for quicker bookings.',
                      style: TextStyle(
                        fontSize: 12,
                        color: CustomerTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_preferencesError != null) ...[
                      Text(
                        _preferencesError!,
                        style: const TextStyle(color: CustomerTheme.danger),
                      ),
                      TextButton(
                        onPressed: _loadPreferences,
                        child: const Text('Retry categories'),
                      ),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availablePreferences.map((pref) {
                        final isSelected = _selectedPreferences.contains(pref);
                        return FilterChip(
                          label: Text(pref),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedPreferences.add(pref);
                              } else {
                                _selectedPreferences.remove(pref);
                              }
                            });
                          },
                          selectedColor: CustomerTheme.primary,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : CustomerTheme.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? CustomerTheme.primary
                                  : CustomerTheme.borderColor,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _saveProfile,
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
