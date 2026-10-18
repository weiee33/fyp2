import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/customer_refresh.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_review_service.dart';
import '../booking/customer_booking_detail_screen.dart';
import 'customer_submit_review_screen.dart';

class CustomerMyReviewsScreen extends StatefulWidget {
  final CustomerReviewService? service;
  const CustomerMyReviewsScreen({super.key, this.service});
  @override
  State<CustomerMyReviewsScreen> createState() =>
      _CustomerMyReviewsScreenState();
}

class _CustomerMyReviewsScreenState extends State<CustomerMyReviewsScreen> {
  late final _service = widget.service ?? CustomerReviewService();
  final List<Map<String, dynamic>> _ready = [];
  bool _more = true, _loadingMore = false;
  int _generation = 0;
  String? _moreError;
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final rows = await _service.getReadyToReview(offset: _ready.length);
      if (mounted && generation == _generation) {
        setState(() {
          _ready.addAll(rows);
          _more = rows.length == 20;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _moreError = 'Could not load more bookings. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  late Future<List<Map<String, dynamic>>> _reviews;
  @override
  void initState() {
    super.initState();
    _reviews = _fetchRows();
  }

  Future<List<Map<String, dynamic>>> _fetchRows() async {
    final generation = ++_generation;
    _loadingMore = false;
    _moreError = null;
    try {
      final results = await Future.wait([
        _service.getMyReviews(),
        _service.getReadyToReview(),
      ]);
      if (mounted && generation == _generation) {
        _ready
          ..clear()
          ..addAll(results[1]);
        _more = results[1].length == 20;
      }
      return results[0];
    } catch (e) {
      if (mounted && generation == _generation) {
        CustomerDialogs.error(context, e);
      }
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
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return DefaultTabController(
      length: 2,
      child: CustomerScaffold(
        appBar: AppBar(
          title: Text(tr('Reviews')),
          bottom: TabBar(
            tabs: [
              Tab(
                height: 56,
                child: Text(tr('Ready To Review'), textAlign: TextAlign.center),
              ),
              Tab(
                height: 56,
                child: Text(tr('My Reviews'), textAlign: TextAlign.center),
              ),
            ],
            labelColor: CustomerTheme.primary,
            unselectedLabelColor: CustomerTheme.textSecondary,
            indicatorSize: TabBarIndicatorSize.tab,
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _reviews,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Could not load your reviews.')),
                    TextButton(onPressed: _reload, child: Text(tr('Retry'))),
                  ],
                ),
              );
            }
            final rows = snapshot.data ?? [];
            return TabBarView(
              children: [
                _reviewList('ready-reviews', [
                  if (_ready.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        tr('No completed services awaiting your review.'),
                      ),
                    ),
                  ..._ready.map(
                    (row) => Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.star_outline,
                          color: CustomerTheme.primary,
                        ),
                        title: Text(
                          row['service_name_snapshot']?.toString() ??
                              tr('Completed service'),
                        ),
                        subtitle: Text(
                          row['provider_name_snapshot']?.toString() ??
                              tr('Service provider'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerSubmitReviewScreen(
                                bookingId: row['booking_id'].toString(),
                                providerId: row['provider_id'].toString(),
                                providerName:
                                    row['provider_name_snapshot']?.toString() ??
                                    'Service provider',
                                serviceName:
                                    row['service_name_snapshot']?.toString() ??
                                    'Completed service',
                              ),
                            ),
                          );
                          if (mounted) await _reload();
                        },
                      ),
                    ),
                  ),
                  if (_moreError != null) Text(tr(_moreError!)),
                  if (_more)
                    TextButton(
                      onPressed: _loadingMore ? null : _loadMore,
                      child: Text(
                        tr(
                          _loadingMore ? 'Loading…' : 'More completed services',
                        ),
                      ),
                    ),
                ]),
                _reviewList('submitted-reviews', [
                  ...(rows.isEmpty
                      ? [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(tr('No reviews yet.')),
                          ),
                        ]
                      : rows
                            .map(
                              (row) => Card(
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row['provider_name']?.toString() ??
                                            tr('Service provider'),
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
                                                    ((row['rating_score']
                                                                as num?)
                                                            ?.toInt() ??
                                                        0)
                                                ? Icons.star
                                                : Icons.star_border,
                                            color: CustomerTheme.primary,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                      if ((row['review_comment']?.toString() ??
                                              '')
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            row['review_comment'].toString(),
                                          ),
                                        ),
                                      if ((row['review_image_url']
                                                  ?.toString() ??
                                              '')
                                          .isNotEmpty)
                                        _ReviewPhoto(
                                          path: row['review_image_url']
                                              .toString(),
                                          service: _service,
                                        ),
                                      Text(
                                        tr(
                                          row['moderation_status'] == 'hidden'
                                              ? 'Hidden by moderation'
                                              : row['is_flagged'] == true
                                              ? 'Under moderation review'
                                              : 'Published',
                                        ),
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
                                        child: Text(tr('View booking')),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList()),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _reviewList(String key, List<Widget> children) => CustomerRefresh(
    onRefresh: _reload,
    child: ListView(
      key: PageStorageKey(key),
      physics: customerScrollPhysics(context),
      padding: const EdgeInsets.all(16),
      children: children,
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
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () =>
                setState(() => _url = widget.service.getImageUrl(widget.path)),
            child: Text(tr('Retry photo')),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(height: 32, child: LinearProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Image.network(
            snapshot.data!,
            height: 160,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(tr('Photo unavailable')),
          ),
        );
      },
    );
  }
}
