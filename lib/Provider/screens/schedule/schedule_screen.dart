import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fyp2/shared/chat/chat_inbox_screen.dart';
import 'booking_map_view_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookings = [];

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) {
          setState(() {
            _bookings = [];
            _loading = false;
          });
        }
        return;
      }

      final providerRow = await _client
          .from('provider_profiles')
          .select('provider_id')
          .eq('user_id', uid)
          .maybeSingle();

      final providerId = providerRow?['provider_id']?.toString();
      if (providerId == null) {
        if (!mounted) return;
        setState(() {
          _bookings = [];
          _loading = false;
        });
        return;
      }

      // Fetch all non-cancelled bookings (past + future)
      final res = await _client
          .from('bookings')
          .select()
          .eq('provider_id', providerId)
          .neq('booking_status', 'Cancelled')
          .order('scheduled_datetime', ascending: true);

      if (!mounted) return;
      setState(() {
        _bookings = List<Map<String, dynamic>>.from(res);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // Check if a booking is expired
  bool _isExpired(Map<String, dynamic> b) {
    final raw = b['scheduled_datetime']?.toString();
    if (raw == null) return false;

    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return false;

    // Expired: time is before now AND status is not Completed
    final status = (b['booking_status'] ?? '').toString().toLowerCase();
    if (status == 'completed' || status == 'cancelled') return false;

    return dt.isBefore(DateTime.now());
  }

  // Split into upcoming and expired
  Map<String, List<Map<String, dynamic>>> _groupBookings() {
    final upcoming = <Map<String, dynamic>>[];
    final expired = <Map<String, dynamic>>[];

    for (final b in _bookings) {
      if (_isExpired(b)) {
        expired.add(b);
      } else {
        upcoming.add(b);
      }
    }

    return {
      'upcoming': upcoming,
      'expired': expired,
    };
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> list) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final b in list) {
      final raw = b['scheduled_datetime']?.toString() ??
          (b['booking_date']?.toString() != null &&
              b['scheduled_time']?.toString() != null
              ? '${b['booking_date']}T${b['scheduled_time']}'
              : null) ??
          b['created_at']?.toString();

      final dt = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
      final key = dt != null
          ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
          : 'Unscheduled';
      map.putIfAbsent(key, () => []).add(b);
    }
    return map;
  }

  int _countToday() {
    final today = DateTime.now();
    return _bookings.where((b) {
      if (_isExpired(b)) return false;
      final raw = b['scheduled_datetime']?.toString();
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt == null) return false;
      return dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day;
    }).length;
  }

  int _countTomorrow() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return _bookings.where((b) {
      if (_isExpired(b)) return false;
      final raw = b['scheduled_datetime']?.toString();
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt == null) return false;
      return dt.year == tomorrow.year &&
          dt.month == tomorrow.month &&
          dt.day == tomorrow.day;
    }).length;
  }

  int _countThisWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    return _bookings.where((b) {
      if (_isExpired(b)) return false;
      final raw = b['scheduled_datetime']?.toString();
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt == null) return false;
      return dt.isAfter(startOfWeek) && dt.isBefore(endOfWeek);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: _lightOrange,
      appBar: AppBar(
        title:  Text(
          tr('Schedule'),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(color: _primaryOrange),
      )
          : RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: _error != null
            ? _errorState()
            : _bookings.isEmpty
            ? _emptyState()
            : _buildContent(),
      ),
    );
  }

  // ==================== Error State ====================
  Widget _errorState() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.shade100, width: 2),
            ),
            child: Icon(
              Icons.error_outline,
              size: 56,
              color: Colors.red.shade400,
            ),
          ),
        ),
        const SizedBox(height: 16),
         Center(
          child: Text(
            tr('Failed to load schedule'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            tr(_error ?? 'Unknown error'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label:  Text(tr('Retry')),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== Empty State ====================
  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _lightOrange,
              shape: BoxShape.circle,
              border: Border.all(color: _borderOrange, width: 2),
            ),
            child: const Icon(
              Icons.calendar_month_outlined,
              size: 56,
              color: _primaryOrange,
            ),
          ),
        ),
        const SizedBox(height: 16),
         Center(
          child: Text(
            tr('No scheduled bookings'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 6),
         Center(
          child: Text(
            tr('Your appointments will appear here'),
            style: TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ==================== Main Content ====================
  Widget _buildContent() {
    final grouped = _groupBookings();
    final upcoming = grouped['upcoming'] ?? [];
    final expired = grouped['expired'] ?? [];

    final upcomingGrouped = _groupByDate(upcoming);
    final expiredGrouped = _groupByDate(expired);

    final upcomingKeys = upcomingGrouped.keys.toList()..sort();
    final expiredKeys = expiredGrouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Stats ----
        Row(
          children: [
            _statCard(
              label: tr('Today'),
              count: _countToday(),
              icon: Icons.today,
              color: _primaryOrange,
            ),
            const SizedBox(width: 10),
            _statCard(
              label: tr('Tomorrow'),
              count: _countTomorrow(),
              icon: Icons.event,
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 10),
            _statCard(
              label: tr('This Week'),
              count: _countThisWeek(),
              icon: Icons.date_range,
              color: const Color(0xFF10B981),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ---- Upcoming Section ----
        if (upcoming.isNotEmpty) ...[
          _sectionTitle(
            icon: Icons.schedule,
            title: tr('Upcoming Schedule'),
            count: upcoming.length,
            color: _primaryOrange,
          ),
          const SizedBox(height: 12),
          ...upcomingKeys.map((dateKey) {
            final items = upcomingGrouped[dateKey]!;
            return _dateGroup(dateKey, items, expired: false);
          }),
          const SizedBox(height: 20),
        ],

        // ---- Expired Section ----
        if (expired.isNotEmpty) ...[
          _sectionTitle(
            icon: Icons.warning_amber_rounded,
            title: tr('Expired Schedule'),
            count: expired.length,
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Please contact the customer to discuss these past appointments.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...expiredKeys.map((dateKey) {
            final items = expiredGrouped[dateKey]!;
            return _dateGroup(dateKey, items, expired: true);
          }),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  // ==================== Section Title ====================
  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          tr(title),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            tr('$count'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // ==================== Date Group ====================
  Widget _dateGroup(
      String dateKey,
      List<Map<String, dynamic>> items, {
        required bool expired,
      }) {
    final headerColor = expired ? Colors.grey.shade700 : _primaryOrange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: headerColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 11,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      tr(_formatHeader(dateKey)),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: expired ? Colors.grey.shade100 : _lightOrange,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: expired ? Colors.grey.shade300 : _borderOrange,
                  ),
                ),
                child: Text(
                  tr('${items.length}'),
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  color: expired ? Colors.grey.shade300 : _borderOrange,
                ),
              ),
            ],
          ),
        ),
        ...items.map((b) => _bookingCard(b, expired: expired)),
        const SizedBox(height: 8),
      ],
    );
  }

  // ==================== Stat Card ====================
  Widget _statCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderOrange),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              tr('$count'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tr(label),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Booking Card ====================
  Widget _bookingCard(Map<String, dynamic> b, {bool expired = false}) {
    final serviceName = b['service_name_snapshot']?.toString() ?? 'Service';
    final address = b['customer_address']?.toString() ?? '';
    final status = b['booking_status']?.toString() ?? 'Pending';
    final scheduledAt = b['scheduled_datetime']?.toString();
    final duration = b['duration_minutes'];
    final amount = b['total_amount'];
    final instructions = b['special_instructions']?.toString() ?? '';

    final cardBg = expired ? Colors.grey.shade50 : Colors.white;
    final borderColor = expired ? Colors.grey.shade300 : _borderOrange;
    final timeBg = expired ? Colors.grey.shade100 : _lightOrange;
    final timeBorder = expired ? Colors.grey.shade300 : _borderOrange;
    final timeColor = expired ? Colors.grey.shade700 : _primaryOrange;

    return Card(
      elevation: 1,
      color: cardBg,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetailsDialog(b),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 62,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: timeBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: timeBorder),
                    ),
                    child: Column(
                      children: [
                        Text(
                          tr(_formatTime(scheduledAt)),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: timeColor,
                          ),
                        ),
                        if (duration != null)
                          Text(
                            tr('${duration}m'),
                            style: TextStyle(
                              fontSize: 10,
                              color: expired
                                  ? Colors.grey.shade600
                                  : Colors.grey,
                            ),
                          )
                        else
                          Text(
                            tr('hrs'),
                            style: TextStyle(
                              fontSize: 10,
                              color: expired
                                  ? Colors.grey.shade600
                                  : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(serviceName),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: expired
                                ? Colors.grey.shade700
                                : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (address.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: expired
                                    ? Colors.grey.shade500
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  tr(address),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: expired
                                        ? Colors.grey.shade500
                                        : Colors.grey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        if (instructions.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.notes,
                                size: 14,
                                color: expired
                                    ? Colors.grey.shade500
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  tr(instructions),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: expired
                                        ? Colors.grey.shade500
                                        : Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (amount != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            tr('RM ${(amount as num).toStringAsFixed(2)}'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: expired
                                  ? Colors.grey.shade600
                                  : _primaryOrange,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  expired ? _expiredChip() : _statusChip(status),
                ],
              ),

              // ---- Expired hint ----
              if (expired) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tr('Please contact the customer to discuss.'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _expiredChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 11, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            tr('EXPIRED'),
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Details Dialog ====================
  Future<void> _showDetailsDialog(Map<String, dynamic> b) async {
    final serviceName = b['service_name_snapshot']?.toString() ?? 'Service';
    final address = b['customer_address']?.toString() ?? '-';
    final status = b['booking_status']?.toString() ?? 'Pending';
    final scheduledAt = b['scheduled_datetime']?.toString();
    final duration = b['duration_minutes'];
    final amount = b['total_amount'];
    final instructions = b['special_instructions']?.toString() ?? '';
    final bookingId = b['booking_id']?.toString() ?? '';
    final customerId = b['customer_id']?.toString();
    final coordinates = b['customer_coordinates']?.toString();
    final expired = _isExpired(b);

    String customerName = 'Customer';
    if (customerId != null) {
      try {
        final row = await _client
            .from('users')
            .select('full_name')
            .eq('user_id', customerId)
            .maybeSingle();
        if (row?['full_name'] != null) {
          customerName = row!['full_name'].toString();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: expired ? Colors.grey.shade200 : _lightOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  expired ? Icons.warning_amber_rounded : Icons.event_note,
                  color: expired ? Colors.grey.shade700 : _primaryOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(expired ? 'Expired Booking' : 'Booking Details'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (expired) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('This appointment has passed. Please contact the customer to discuss.'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _detailRow('Customer', customerName, Icons.person_outline),
                _detailRow('Service', serviceName, Icons.build_outlined),
                _detailRow('Status', status, Icons.info_outline),
                _detailRow(
                  'Date & Time',
                  _formatFullDateTime(scheduledAt),
                  Icons.access_time,
                ),
                if (duration != null)
                  _detailRow('Duration', '$duration minutes',
                      Icons.timer_outlined),
                if (amount != null)
                  _detailRow(
                    'Total',
                    'RM ${(amount as num).toStringAsFixed(2)}',
                    Icons.attach_money,
                  ),
                _detailRow('Address', address, Icons.location_on_outlined),
                if (instructions.isNotEmpty)
                  _detailRow(
                      'Instructions', instructions, Icons.notes_outlined),
                if (bookingId.isNotEmpty)
                  _detailRow(
                    'Booking ID',
                    '${bookingId.substring(0, 8)}...',
                    Icons.confirmation_number_outlined,
                  ),
                if (coordinates != null && coordinates.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _mapPreview(coordinates, address),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                _buildActionButtons(
                  ctx: ctx,
                  bookingId: bookingId,
                  status: status,
                  customerId: customerId,
                  customerName: customerName,
                  expired: expired,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: _primaryOrange),
              child:  Text(tr('Close')),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Map Preview ====================
  Widget _mapPreview(String coordinates, String address) {
    final parts = coordinates.split(',');
    double? lat, lng;
    if (parts.length == 2) {
      lat = double.tryParse(parts[0].trim());
      lng = double.tryParse(parts[1].trim());
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _lightOrange,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderOrange),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _primaryOrange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text(
                  tr('Customer Location'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _primaryOrange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(lat != null && lng != null ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}' : coordinates),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _openMap(lat, lng, address),
                  child:  Text(
                    tr('View on Map →'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _primaryOrange,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMap(double? lat, double? lng, String address) async {
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
          content: Text(tr('No coordinates available for this booking')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context, rootNavigator: true).pop();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingMapViewScreen(
          latitude: lat,
          longitude: lng,
          address: address,
        ),
      ),
    );
  }

  // ==================== Action Buttons ====================
  Widget _buildActionButtons({
    required BuildContext ctx,
    required String bookingId,
    required String status,
    required String? customerId,
    required String customerName,
    required bool expired,
  }) {
    final lowerStatus = status.toLowerCase();
    final isCompleted = lowerStatus == 'completed';
    final isCancelled = lowerStatus == 'cancelled';
    final isInProgress = lowerStatus == 'in-progress';
    final isConfirmed = lowerStatus == 'confirmed';
    final isPending = lowerStatus == 'pending';

    final buttons = <Widget>[];

    if (customerId != null && !isCompleted && !isCancelled) {
      buttons.add(
        _actionButton(
          label: tr('Chat with Customer'),
          icon: Icons.chat_bubble_outline,
          color: _primaryOrange,
          outlined: true,
          onTap: () {
            Navigator.pop(ctx);
            _openChat(bookingId);
          },
        ),
      );
    }

    // Show "Start Job" only if not expired
    if (!expired && (isConfirmed || isPending)) {
      buttons.add(
        _actionButton(
          label: tr('Start Job'),
          icon: Icons.play_arrow,
          color: const Color(0xFF3B82F6),
          onTap: () async {
            await _updateStatus(bookingId, 'In-Progress');
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    if (isInProgress) {
      buttons.add(
        _actionButton(
          label: tr('Mark as Completed'),
          icon: Icons.check_circle,
          color: const Color(0xFF10B981),
          onTap: () async {
            await _updateStatus(bookingId, 'Completed');
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    // Show "Mark as Completed" for expired (so they can clean up old bookings)
    if (expired && !isCompleted && !isCancelled) {
      buttons.add(
        _actionButton(
          label: tr('Mark as Completed'),
          icon: Icons.check_circle,
          color: const Color(0xFF10B981),
          onTap: () async {
            await _updateStatus(bookingId, 'Completed');
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    if (!isCompleted && !isCancelled) {
      buttons.add(
        _actionButton(
          label: tr('Cancel Booking'),
          icon: Icons.cancel_outlined,
          color: Colors.red.shade600,
          outlined: true,
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(
                title:  Text(tr('Cancel Booking')),
                content:  Text(
                  tr('Are you sure you want to cancel this booking?'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child:  Text(tr('No')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child:  Text(tr('Yes, Cancel')),
                  ),
                ],
              ),
            );
            if (confirm != true) return;
            await _updateStatus(bookingId, 'Cancelled');
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: buttons
          .map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: b,
      ))
          .toList(),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(
            tr(label),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          tr(label),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  // ==================== Update Status ====================
  Future<void> _updateStatus(String bookingId, String newStatus) async {
    try {
      // 1. Get the booking (to know total_amount, provider_id)
      final bookingRow = await _client
          .from('bookings')
          .select()
          .eq('booking_id', bookingId)
          .maybeSingle();

      if (bookingRow == null) {
        throw Exception('Booking not found');
      }

      // 2. Prepare update data
      final updates = <String, dynamic>{
        'booking_status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final now = DateTime.now().toUtc().toIso8601String();

      if (newStatus == 'In-Progress') {
        updates['started_at'] = now;
      } else if (newStatus == 'Completed') {
        updates['completed_at'] = now;
      } else if (newStatus == 'Cancelled') {
        updates['cancelled_at'] = now;
      }

      // 3. Update the booking
      await _client
          .from('bookings')
          .update(updates)
          .eq('booking_id', bookingId);

      // 4. If just marked as Completed, insert into provider_earnings
      if (newStatus == 'Completed') {
        await _syncEarningsRecord(bookingRow);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(tr('Booking marked as $newStatus')),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Failed to update: $e')),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ==================== Sync Earnings Record ====================
  Future<void> _syncEarningsRecord(Map<String, dynamic> bookingRow) async {
    try {
      final bookingId = bookingRow['booking_id']?.toString();
      final providerId = bookingRow['provider_id']?.toString();
      final grossAmount =
          (bookingRow['total_amount'] as num?)?.toDouble() ?? 0.0;

      if (bookingId == null || providerId == null) return;

      // 1. Check if an earnings record already exists for this booking
      final existing = await _client
          .from('provider_earnings')
          .select('earnings_id')
          .eq('booking_id', bookingId)
          .maybeSingle();

      if (existing != null) {
        // Already exists, don't insert again
        return;
      }

      // 2. Compute platform fee
      //    (net_earnings is auto-generated by the DB)
      const platformFeePercent = 0.10; // 10% platform fee
      final platformFee = grossAmount * platformFeePercent;

      // 3. Insert earnings record (without net_earnings)
      await _client.from('provider_earnings').insert({
        'provider_id': providerId,
        'booking_id': bookingId,
        'gross_amount': grossAmount,
        'platform_fee': platformFee,
        'payout_status': 'Pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Failed to sync earnings record: $e');
    }
  }

  // ==================== Open Chat ====================
  void _openChat(String bookingId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ChatInboxScreen(customer: false),
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              tr(label),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              tr(value),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Status Chip ====================
  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'completed':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        icon = Icons.check_circle;
        break;
      case 'cancelled':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        icon = Icons.cancel;
        break;
      case 'in-progress':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        icon = Icons.play_circle;
        break;
      case 'confirmed':
        bg = _lightOrange;
        fg = _primaryOrange;
        icon = Icons.verified;
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        icon = Icons.pending;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            tr(status.toUpperCase()),
            style: TextStyle(
              fontSize: 10,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Formatters ====================
  String _formatHeader(String dateKey) {
    if (dateKey == 'Unscheduled') return 'Unscheduled';
    try {
      final dt = DateTime.parse(dateKey);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(dt.year, dt.month, dt.day);
      final diff = target.difference(today).inDays;

      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      if (diff == -1) return 'Yesterday';

      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return dateKey;
    }
  }

  String _formatFullDateTime(String? raw) {
    if (raw == null) return '--';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final day = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$day ${months[dt.month - 1]} ${dt.year}, $h:$m';
    } catch (_) {
      return '--';
    }
  }

  String _formatTime(String? raw) {
    if (raw == null) return '--:--';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '--:--';
    }
  }
}