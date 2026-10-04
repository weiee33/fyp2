import '../../widgets/account_widgets.dart';
import '../../widgets/malaysia_phone_field.dart';
import '../../widgets/customer_dialogs.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_profile_service.dart';
import '../../services/customer_image_service.dart';

class CustomerEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? profileData;
  final CustomerProfileService? service;

  const CustomerEditProfileScreen({super.key, this.profileData, this.service});

  @override
  State<CustomerEditProfileScreen> createState() =>
      _CustomerEditProfileScreenState();
}

class _CustomerEditProfileScreenState extends State<CustomerEditProfileScreen> {
  String _bio = "";
  String? _gender, _birthday;
  bool _dirty = false;
  late final _profileService = widget.service ?? CustomerProfileService();
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
      text: MalaysiaPhone.national(
        widget.profileData?['phone']?.toString() ?? '',
      ),
    );
    _existingPhotoUrl = widget.profileData?['profile_photo_url'];
    _bio = widget.profileData?['bio']?.toString() ?? '';
    _gender = widget.profileData?['gender'];
    _birthday = widget.profileData?['birthday'];

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
        _dirty = true;
        _pickedImageBytes = bytes;
        _pickedImageExt = ext;
        _uploadedPhotoUrl = null;
      });
    } catch (e) {
      if (!mounted) return;
      await CustomerDialogs.error(context, e);
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
    if (_nameController.text.trim().isEmpty ||
        MalaysiaPhone.validate(_phoneController.text) != null) {
      setState(() => _isSaving = false);
      await CustomerDialogs.show(
        context,
        message: 'Please enter your name and a valid Malaysian mobile number.',
      );
      return;
    }

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
        phone: MalaysiaPhone.international(_phoneController.text),
        bio: _bio,
        gender: _gender,
        birthday: _birthday,
        photoUrl: _uploadedPhotoUrl,
        preferences: _selectedPreferences.toList(),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      await CustomerDialogs.show(
        context,
        message: 'Profile updated successfully',
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await CustomerDialogs.show(
        context,
        message: 'Failed to update profile: $e',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _edit(String field) async {
    final controller = TextEditingController(
      text: switch (field) {
        'Name' => _nameController.text,
        'Bio' => _bio,
        _ => _phoneController.text,
      },
    );
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $field'),
        content: Form(
          key: form,
          child: field == 'Phone'
              ? MalaysiaPhoneField(controller: controller)
              : TextFormField(
                  controller: controller,
                  autofocus: true,
                  maxLength: field == 'Bio' ? 300 : 100,
                  maxLines: field == 'Bio' ? 4 : 1,
                  validator: (v) =>
                      field == 'Name' && (v?.trim().isEmpty ?? true)
                      ? 'Name is required'
                      : null,
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    // Dialog closing animation may still reference the controller this frame.
    if (value != null && mounted) {
      setState(() {
        _dirty = true;
        switch (field) {
          case 'Name':
            _nameController.text = value;
          case 'Bio':
            _bio = value;
          case 'Phone':
            _phoneController.text = value;
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
  }

  Future<void> _pickGender() async {
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Gender'),
        children: [
          for (final label in ['Female', 'Male', 'Prefer not to say'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, label),
              child: Text(label),
            ),
        ],
      ),
    );
    if (mounted && value != null)
      setState(() {
        _gender = value;
        _dirty = true;
      });
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse(_birthday ?? '') ?? DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (mounted && date != null)
      setState(() {
        _birthday =
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        _dirty = true;
      });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_isSaving,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || _isSaving) return;
      if (await CustomerDialogs.confirm(
            context,
            title: 'Discard changes?',
            message: 'Your unsaved profile changes will be lost.',
          ) &&
          mounted) {
        setState(() => _dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: const Text('Save'),
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.all(10),
              children: [
                AccountGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: InkWell(
                          onTap: _showImageSourceSheet,
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 38,
                                backgroundColor: CustomerTheme.primarySurface,
                                backgroundImage: _pickedImageBytes != null
                                    ? MemoryImage(_pickedImageBytes!)
                                    : (_existingPhotoUrl?.isNotEmpty ?? false)
                                    ? NetworkImage(_existingPhotoUrl!)
                                    : null,
                                child:
                                    _pickedImageBytes == null &&
                                        (_existingPhotoUrl?.isEmpty ?? true)
                                    ? const Icon(
                                        Icons.person,
                                        color: CustomerTheme.primary,
                                        size: 44,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_outlined, size: 18),
                                  Text(' Edit photo'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                AccountGroup(
                  children: [
                    AccountRow(
                      label: 'Name',
                      value: _nameController.text,
                      onTap: () => _edit('Name'),
                    ),
                    AccountRow(
                      label: 'Bio',
                      value: _bio.isEmpty ? 'Set now' : _bio,
                      onTap: () => _edit('Bio'),
                    ),
                  ],
                ),
                AccountGroup(
                  children: [
                    AccountRow(
                      label: 'Gender',
                      value: _gender ?? 'Set now',
                      onTap: _pickGender,
                    ),
                    AccountRow(
                      label: 'Birthday',
                      value: _birthday ?? 'Set now',
                      onTap: _pickBirthday,
                    ),
                  ],
                ),
                AccountGroup(
                  children: [
                    AccountRow(
                      label: 'Phone',
                      value: maskedPhone('+60${_phoneController.text}'),
                      onTap: () => _edit('Phone'),
                    ),
                    AccountRow(
                      label: 'Email',
                      value: maskedEmail(
                        widget.profileData?['email']?.toString() ?? '',
                      ),
                      subtitle: 'Verified sign-in email',
                    ),
                  ],
                ),
                AccountGroup(
                  title: 'Service preferences',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Choose services you frequently need.'),
                          const SizedBox(height: 12),
                          if (_preferencesError != null) ...[
                            Text(_preferencesError!),
                            TextButton(
                              onPressed: _loadPreferences,
                              child: const Text('Retry categories'),
                            ),
                          ],
                          Wrap(
                            spacing: 8,
                            children: _availablePreferences
                                .map(
                                  (pref) => FilterChip(
                                    label: Text(pref),
                                    selected: _selectedPreferences.contains(
                                      pref,
                                    ),
                                    onSelected: (selected) => setState(() {
                                      _dirty = true;
                                      if (selected) {
                                        _selectedPreferences.add(pref);
                                      } else {
                                        _selectedPreferences.remove(pref);
                                      }
                                    }),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Your birthday and gender are optional and are not shown to providers.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ],
            ),
    ),
  );
}
