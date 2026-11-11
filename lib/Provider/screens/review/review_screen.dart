import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/profile_service.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final _service = ProfileService();
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final list = await _service.getMyReviews();
      if (!mounted) return;
      setState(() {
        _reviews = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Failed to load reviews: {0}', [e])),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double get _avgRating {
    if (_reviews.isEmpty) return 0;
    final sum = _reviews.fold<int>(
      0,
          (acc, r) => acc + ((r['rating_score'] as num?)?.toInt() ?? 0),
    );
    return sum / _reviews.length;
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(tr('My Reviews')),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryOrange,
          child: _reviews.isEmpty
              ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Icon(Icons.star_border, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  tr('No reviews yet'),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          )
              : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summaryCard(),
              const SizedBox(height: 16),
              ..._reviews.map((r) => _reviewCard(r)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Card(
      elevation: 1,
      color: _lightOrange,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              children: [
                Text(
                  _avgRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _primaryOrange,
                  ),
                ),
                Row(
                  children: List.generate(5, (i) {
                    final filled = i < _avgRating.round();
                    return Icon(
                      filled ? Icons.star : Icons.star_border,
                      size: 16,
                      color: Colors.orange,
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('{0} review(s)', [_reviews.length]),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Average rating from all visible reviews'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final rating = (r['rating_score'] as num?)?.toInt() ?? 0;
    final comment = r['review_comment']?.toString() ?? '';
    final verified = r['is_verified_booking'] == true;

    final createdAt = r['created_at'] != null
        ? DateTime.tryParse(r['created_at'].toString())?.toLocal()
        : null;
    final dateStr = createdAt != null
        ? '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
        : '';

    final customerRaw = r['customer'];
    String customerName = 'Unknown';
    String customerPhoto = '';

    if (customerRaw is Map) {
      customerName = customerRaw['full_name']?.toString() ?? 'No Name';
      final rawPhoto = customerRaw['profile_photo_url']?.toString() ?? '';

      if (rawPhoto.isNotEmpty) {
        if (rawPhoto.startsWith('http')) {
          customerPhoto = rawPhoto;
        } else {
          customerPhoto = Supabase.instance.client.storage
              .from('profiles')
              .getPublicUrl(rawPhoto);
        }
      }
    }

    final initial = customerName.isNotEmpty && customerName != 'Unknown'
        ? customerName[0].toUpperCase()
        : '?';

    return Card(
      elevation: 1,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _lightOrange,
                  backgroundImage: customerPhoto.isNotEmpty
                      ? NetworkImage(customerPhoto)
                      : null,
                  onBackgroundImageError:
                  customerPhoto.isNotEmpty ? (_, __) {} : null,
                  child: customerPhoto.isEmpty
                      ? Text(
                    initial,
                    style: const TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              customerName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified, size: 12, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    tr('Verified'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                        (i) => Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      size: 16,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                comment,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}