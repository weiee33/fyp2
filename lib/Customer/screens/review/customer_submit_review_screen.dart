import '../../widgets/customer_dialogs.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_review_service.dart';
import '../../services/customer_image_service.dart';

class CustomerSubmitReviewScreen extends StatefulWidget {
  final String bookingId;
  final String providerId;
  final String providerName;
  final String serviceName;

  const CustomerSubmitReviewScreen({
    super.key,
    required this.bookingId,
    required this.providerId,
    required this.providerName,
    required this.serviceName,
  });

  @override
  State<CustomerSubmitReviewScreen> createState() =>
      _CustomerSubmitReviewScreenState();
}

class _CustomerSubmitReviewScreenState extends State<CustomerSubmitReviewScreen>
    with SingleTickerProviderStateMixin {
  final CustomerReviewService _reviewService = CustomerReviewService();
  final TextEditingController _commentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isVerifying = true;
  bool _isEligible = false;
  bool _isSubmitting = false;
  String? _eligibilityError;

  int _selectedRating = 0;
  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;
  String? _uploadedImagePath;

  late AnimationController _starAnimController;

  @override
  void initState() {
    super.initState();
    _starAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _verifyEligibility();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _starAnimController.dispose();
    super.dispose();
  }

  Future<void> _verifyEligibility() async {
    setState(() {
      _isVerifying = true;
      _eligibilityError = null;
    });
    try {
      // Validates closed-loop restriction rule[cite: 452]
      final eligible = await _reviewService.verifyBookingEligibility(
        widget.bookingId,
      );
      if (mounted) {
        setState(() {
          _isEligible = eligible;
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _eligibilityError =
              'Could not check review eligibility. Please retry.';
        });
        CustomerDialogs.error(context, e);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      CustomerImageService.validate(bytes, ext);
      if (!mounted) return;
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageExt = ext;
        _uploadedImagePath = null;
      });
    } catch (e) {
      if (!mounted) return;
      CustomerDialogs.error(context, e);
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

  Future<void> _submitReview() async {
    if (_isSubmitting) return;
    if (_selectedRating == 0) {
      CustomerDialogs.show(context, message: 'Please select a star rating.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      // Upload Review Image if provided[cite: 452]
      if (_pickedImageBytes != null &&
          _pickedImageExt != null &&
          _uploadedImagePath == null) {
        _uploadedImagePath = await _reviewService.uploadReviewImage(
          _pickedImageBytes!,
          _pickedImageExt!,
          widget.bookingId,
        );
      }

      // Save Rating and Comment to database[cite: 452]
      await _reviewService.submitReview(
        bookingId: widget.bookingId,
        ratingScore: _selectedRating,
        comment: _commentController.text.trim().isNotEmpty
            ? _commentController.text.trim()
            : null,
        imageUrl: _uploadedImagePath,
      );

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      // Show Success Modal
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: CustomerTheme.success,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Review Submitted!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Thank you for sharing your experience.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CustomerTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(
                    context,
                    true,
                  ); // pop screen, return true for refresh
                },
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      CustomerDialogs.error(context, e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CustomerTheme.lightTheme,
      child: Scaffold(
        backgroundColor: CustomerTheme.background,
        appBar: AppBar(
          title: const Text('Rate Service'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _isVerifying
            ? const Center(
                child: CircularProgressIndicator(color: CustomerTheme.primary),
              )
            : _eligibilityError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_eligibilityError!),
                      TextButton(
                        onPressed: _verifyEligibility,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : !_isEligible
            ? _buildIneligibleView()
            : _buildReviewForm(),
      ),
    );
  }

  /// Displayed if booking is unverified/uncompleted[cite: 452]
  Widget _buildIneligibleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Review Locked',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: CustomerTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only your completed, paid bookings can be reviewed. Each booking can have one review.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CustomerTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  /// Main Review Form
  Widget _buildReviewForm() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                // Header
                Center(
                  child: Text(
                    'How was your service with',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    widget.providerName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: CustomerTheme.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    widget.serviceName,
                    style: const TextStyle(
                      fontSize: 14,
                      color: CustomerTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Animated Stars
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    final isSelected = starValue <= _selectedRating;
                    return GestureDetector(
                      onTap: _isSubmitting
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedRating = starValue);
                              _starAnimController.forward(from: 0.0);
                            },
                      child: AnimatedScale(
                        scale: isSelected ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.elasticOut,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            isSelected
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 48,
                            color: isSelected
                                ? Colors.orange
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),

                // Text Input
                const Text(
                  'Share your experience',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _commentController,
                  maxLines: 4,
                  maxLength: 2000,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Were they professional? Was the issue fixed?',
                  ),
                ),
                const SizedBox(height: 24),

                // Optional Image Upload[cite: 451, 452]
                const Text(
                  'Attach Photo (Optional)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (_pickedImageBytes == null)
                  InkWell(
                    onTap: _isSubmitting ? null : _showImageSourceSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: CustomerTheme.borderColor,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: CustomerTheme.primary,
                            size: 28,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add photo',
                            style: TextStyle(
                              color: CustomerTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Stack(
                    children: [
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: MemoryImage(_pickedImageBytes!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() {
                                  _pickedImageBytes = null;
                                  _pickedImageExt = null;
                                  _uploadedImagePath = null;
                                }),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Submit Button Sticky Footer
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReview,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Submit Review'),
            ),
          ),
        ],
      ),
    );
  }
}
