import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_review_service.dart';
import '../booking/customer_booking_detail_screen.dart';

class CustomerMyReviewsScreen extends StatefulWidget {
  const CustomerMyReviewsScreen({super.key});
  @override
  State<CustomerMyReviewsScreen> createState() =>
      _CustomerMyReviewsScreenState();
}

class _CustomerMyReviewsScreenState extends State<CustomerMyReviewsScreen> {
  final _service = CustomerReviewService();
  late Future<List<Map<String, dynamic>>> _reviews;
  @override
  void initState() {
    super.initState();
    _reviews = _fetchRows();
  }

  Future<List<Map<String, dynamic>>> _fetchRows() async {
    try {
      return await _service.getMyReviews();
    } catch (e) {
      if (mounted) CustomerDialogs.error(context, e);
      rethrow;
    }
  }

  Future<void> _reload() async {
    final request = _fetchRows();
    setState(() => _reviews = request);
    try {
      await request;
    } catch (_) {
      /* FutureBuilder displays this failure. */
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Reviews')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _reviews,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your reviews.'),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        final rows = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: rows.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No reviews yet. Open a completed, paid booking to share your experience.',
                      ),
                    ),
                  ]
                : rows
                      .map(
                        (row) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row['provider_name']?.toString() ??
                                      'Service provider',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                if (row['service_name'] != null)
                                  Text(row['service_name'].toString()),
                                const SizedBox(height: 8),
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i <
                                              ((row['rating_score'] as num?)
                                                      ?.toInt() ??
                                                  0)
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: CustomerTheme.primary,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                if ((row['review_comment']?.toString() ?? '')
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      row['review_comment'].toString(),
                                    ),
                                  ),
                                if ((row['review_image_url']?.toString() ?? '')
                                    .isNotEmpty)
                                  _ReviewPhoto(
                                    path: row['review_image_url'].toString(),
                                    service: _service,
                                  ),
                                Text(
                                  row['moderation_status'] == 'hidden'
                                      ? 'Hidden by moderation'
                                      : row['is_flagged'] == true
                                      ? 'Under moderation review'
                                      : 'Published',
                                  style: const TextStyle(
                                    color: CustomerTheme.textSecondary,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CustomerBookingDetailScreen(
                                            bookingId: row['booking_id']
                                                .toString(),
                                          ),
                                    ),
                                  ),
                                  child: const Text('View booking'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
          ),
        );
      },
    ),
  );
}

class _ReviewPhoto extends StatefulWidget {
  final String path;
  final CustomerReviewService service;
  const _ReviewPhoto({required this.path, required this.service});
  @override
  State<_ReviewPhoto> createState() => _ReviewPhotoState();
}

class _ReviewPhotoState extends State<_ReviewPhoto> {
  late Future<String> _url;
  @override
  void initState() {
    super.initState();
    _url = widget.service.getImageUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return TextButton(
          onPressed: () =>
              setState(() => _url = widget.service.getImageUrl(widget.path)),
          child: const Text('Retry photo'),
        );
      if (!snapshot.hasData)
        return const SizedBox(height: 32, child: LinearProgressIndicator());
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.network(
          snapshot.data!,
          height: 160,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('Photo unavailable'),
        ),
      );
    },
  );
}
