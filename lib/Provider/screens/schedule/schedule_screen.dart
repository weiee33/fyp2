import 'package:intl/intl.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fyp2/shared/chat/chat_inbox_screen.dart';
import 'package:fyp2/Provider/services/booking_service.dart';
import 'booking_map_view_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _client = Supabase.instance.client;
  final _bookingService = BookingService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookings = [];

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);
  static const _successGreen = Color(0xFF10B981);

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

      final now = DateTime.now().toUtc().toIso8601String();

      final res = await _client
          .from('bookings')
          .select()
          .eq('provider_id', providerId)
          .not('booking_status', 'in', '(Cancelled,Completed)')
          .gte('scheduled_datetime', now)
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

  bool _isExpired(Map<String, dynamic> b) {
    final raw = b['scheduled_datetime']?.toString();
    if (raw == null) return false;

    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return false;

    final status = (b['booking_status'] ?? '').toString().toLowerCase();
    if (status == 'completed' || status == 'cancelled') return false;

    return dt.isBefore(DateTime.now());
  }

  List<Map<String, dynamic>> _groupUpcoming() {
    final upcoming = <Map<String, dynamic>>[];
    for (final b in _bookings) {
      if (!_isExpired(b)) upcoming.add(b);
    }
    return upcoming;
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> list,
      ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final b in list) {
      final raw =
          b['scheduled_datetime']?.toString() ??
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
          isZh ? '日程' : (isMs ? 'Jadual' : 'Schedule'),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
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
            ? _errorState(isZh, isMs)
            : _bookings.isEmpty
            ? _emptyState(isZh, isMs)
            : _buildContent(isZh, isMs),
      ),
    );
  }

  Widget _errorState(bool isZh, bool isMs) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
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
            isZh
                ? '加载日程失败'
                : (isMs ? 'Gagal memuatkan jadual' : 'Failed to load schedule'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            _error ??
                (isZh
                    ? '未知错误'
                    : (isMs ? 'Ralat tidak diketahui' : 'Unknown error')),
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
            label: Text(isZh ? '重试' : (isMs ? 'Cuba lagi' : 'Retry')),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(bool isZh, bool isMs) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
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
            isZh
                ? '暂无已安排的预约'
                : (isMs
                ? 'Tiada tempahan yang dijadualkan'
                : 'No scheduled bookings'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            isZh
                ? '您的预约将显示在这里'
                : (isMs
                ? 'Temu janji anda akan dipaparkan di sini'
                : 'Your appointments will appear here'),
            style: const TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(bool isZh, bool isMs) {
    final upcoming = _groupUpcoming();
    final upcomingGrouped = _groupByDate(upcoming);
    final upcomingKeys = upcomingGrouped.keys.toList()..sort();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Row(
          children: [
            _statCard(
              label: isZh ? '今天' : (isMs ? 'Hari Ini' : 'Today'),
              count: _countToday(),
              icon: Icons.today,
              color: _primaryOrange,
            ),
            const SizedBox(width: 10),
            _statCard(
              label: isZh ? '明天' : (isMs ? 'Esok' : 'Tomorrow'),
              count: _countTomorrow(),
              icon: Icons.event,
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 10),
            _statCard(
              label: isZh ? '本周' : (isMs ? 'Minggu Ini' : 'This Week'),
              count: _countThisWeek(),
              icon: Icons.date_range,
              color: _successGreen,
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (upcoming.isNotEmpty) ...[
          _sectionTitle(
            icon: Icons.schedule,
            title: isZh
                ? '即将到来'
                : (isMs ? 'Akan Datang' : 'Upcoming Schedule'),
            count: upcoming.length,
            color: _primaryOrange,
          ),
          const SizedBox(height: 12),
          ...upcomingKeys.map((dateKey) {
            final items = upcomingGrouped[dateKey]!;
            return _dateGroup(dateKey, items);
          }),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                isZh
                    ? '暂无即将到来的预约'
                    : (isMs
                    ? 'Tiada tempahan akan datang'
                    : 'No upcoming bookings'),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),

        const SizedBox(height: 16),
      ],
    );
  }

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
          title,
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
            '$count',
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

  Widget _dateGroup(String dateKey, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _primaryOrange,
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
                      _formatHeader(dateKey),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _lightOrange,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _borderOrange),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    color: _primaryOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: _borderOrange)),
            ],
          ),
        ),
        ...items.map((b) => _bookingCard(b)),
        const SizedBox(height: 8),
      ],
    );
  }

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
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
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

  Widget _bookingCard(Map<String, dynamic> b) {
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final serviceName = b['service_name_snapshot']?.toString() ??
        (isZh ? '服务' : (isMs ? 'Perkhidmatan' : 'Service'));
    final address = b['customer_address']?.toString() ?? '';
    final status = b['booking_status']?.toString() ?? 'Pending';
    final scheduledAt = b['scheduled_datetime']?.toString();
    final duration = b['duration_minutes'];
    final amount = b['total_amount'];
    final instructions = b['special_instructions']?.toString() ?? '';

    return Card(
      elevation: 1,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
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
                      color: _lightOrange,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _borderOrange),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _formatTime(scheduledAt),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _primaryOrange,
                          ),
                        ),
                        if (duration != null)
                          Text(
                            '${duration}m',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          )
                        else
                          Text(
                            isZh ? '小时' : (isMs ? 'jam' : 'hrs'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
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
                          serviceName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (address.isNotEmpty)
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  address,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
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
                              const Icon(
                                Icons.notes,
                                size: 14,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  instructions,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
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
                            'RM ${(amount as num).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _primaryOrange,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _statusChip(status, isZh, isMs),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetailsDialog(Map<String, dynamic> b) async {
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final serviceName = b['service_name_snapshot']?.toString() ??
        (isZh ? '服务' : (isMs ? 'Perkhidmatan' : 'Service'));
    final address = b['customer_address']?.toString() ?? '-';
    final status = b['booking_status']?.toString() ?? 'Pending';
    final scheduledAt = b['scheduled_datetime']?.toString();
    final duration = b['duration_minutes'];
    final amount = b['total_amount'];
    final instructions = b['special_instructions']?.toString() ?? '';
    final bookingId = b['booking_id']?.toString() ?? '';
    final customerId = b['customer_id']?.toString();
    final coordinates = b['customer_coordinates']?.toString();

    String customerName = isZh ? '客户' : (isMs ? 'Pelanggan' : 'Customer');
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
          // 👇 改成 X 按钮放在右上角
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _lightOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.event_note,
                  color: _primaryOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isZh ? '预约详情' : (isMs ? 'Butiran Tempahan' : 'Booking Details'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow(
                  isZh ? '客户' : (isMs ? 'Pelanggan' : 'Customer'),
                  customerName,
                  Icons.person_outline,
                ),
                _detailRow(
                  isZh ? '服务' : (isMs ? 'Perkhidmatan' : 'Service'),
                  serviceName,
                  Icons.build_outlined,
                ),
                _detailRow(
                  isZh ? '状态' : (isMs ? 'Status' : 'Status'),
                  status,
                  Icons.info_outline,
                ),
                _detailRow(
                  isZh ? '日期和时间' : (isMs ? 'Tarikh & Masa' : 'Date & Time'),
                  _formatFullDateTime(scheduledAt),
                  Icons.access_time,
                ),
                if (duration != null)
                  _detailRow(
                    isZh ? '时长' : (isMs ? 'Tempoh' : 'Duration'),
                    '$duration ${isZh ? '分钟' : (isMs ? 'minit' : 'minutes')}',
                    Icons.timer_outlined,
                  ),
                if (amount != null)
                  _detailRow(
                    isZh ? '总计' : (isMs ? 'Jumlah' : 'Total'),
                    'RM ${(amount as num).toStringAsFixed(2)}',
                    Icons.attach_money,
                  ),
                _detailRow(
                  isZh ? '地址' : (isMs ? 'Alamat' : 'Address'),
                  address,
                  Icons.location_on_outlined,
                ),
                if (instructions.isNotEmpty)
                  _detailRow(
                    isZh ? '指示' : (isMs ? 'Arahan' : 'Instructions'),
                    instructions,
                    Icons.notes_outlined,
                  ),
                if (bookingId.isNotEmpty)
                  _detailRow(
                    isZh ? '预约号' : (isMs ? 'ID Tempahan' : 'Booking ID'),
                    '${bookingId.substring(0, 8)}...',
                    Icons.confirmation_number_outlined,
                  ),
                if (coordinates != null && coordinates.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _mapPreview(coordinates, address, isZh, isMs),
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
                  isZh: isZh,
                  isMs: isMs,
                ),
              ],
            ),
          ),
          // 去掉原来的 actions 配置
          actions: null,
        ),
      ),
    );
  }

  Widget _mapPreview(String coordinates, String address, bool isZh, bool isMs) {
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
                  isZh
                      ? '客户位置'
                      : (isMs ? 'Lokasi Pelanggan' : 'Customer Location'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _primaryOrange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lat != null && lng != null
                      ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
                      : coordinates,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _openMap(lat, lng, address, isZh, isMs),
                  child: Text(
                    isZh
                        ? '在地图上查看 →'
                        : (isMs ? 'Lihat di Peta →' : 'View on Map →'),
                    style: const TextStyle(
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

  Future<void> _openMap(
      double? lat, double? lng, String address, bool isZh, bool isMs) async {
    if (lat == null || lng == null) {
      if (!mounted) return;
      _showAppDialog(
        title: 'Error',
        message: isZh
            ? '该预约没有可用的坐标'
            : (isMs
            ? 'Tiada koordinat tersedia untuk tempahan ini'
            : 'No coordinates available for this booking'),
        isError: true,
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

  Widget _buildActionButtons({
    required BuildContext ctx,
    required String bookingId,
    required String status,
    required String? customerId,
    required String customerName,
    required bool isZh,
    required bool isMs,
  }) {
    final lowerStatus = status.toLowerCase();
    final isInProgress = lowerStatus == 'in-progress';
    final isConfirmed = lowerStatus == 'confirmed';
    final isPending = lowerStatus == 'pending';

    final buttons = <Widget>[];

    if (customerId != null) {
      buttons.add(
        _actionButton(
          label: isZh
              ? '与客户聊天'
              : (isMs ? 'Sembang dengan Pelanggan' : 'Chat with Customer'),
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

    if (isPending) {
      buttons.add(
        _actionButton(
          label: isZh
              ? '接受预约'
              : (isMs ? 'Terima Tempahan' : 'Accept Booking'),
          icon: Icons.check_circle_outline,
          color: _successGreen,
          onTap: () async {
            await _updateStatus(bookingId, 'Confirmed', isZh, isMs);
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    if (isPending) {
      buttons.add(
        _actionButton(
          label: isZh
              ? '取消预约'
              : (isMs ? 'Batal Tempahan' : 'Cancel Booking'),
          icon: Icons.cancel_outlined,
          color: Colors.red.shade600,
          outlined: true,
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(
                title: Text(isZh
                    ? '取消预约'
                    : (isMs ? 'Batal Tempahan' : 'Cancel Booking')),
                content: Text(
                  isZh
                      ? '你确定要取消这个预约吗？'
                      : (isMs
                      ? 'Adakah anda pasti mahu membatalkan tempahan ini?'
                      : 'Are you sure you want to cancel this booking?'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(isZh ? '不' : (isMs ? 'Tidak' : 'No')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(isZh
                        ? '是的，取消'
                        : (isMs ? 'Ya, Batal' : 'Yes, Cancel')),
                  ),
                ],
              ),
            );
            if (confirm != true) return;
            await _cancelBooking(bookingId, isZh, isMs);
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    if (isConfirmed) {
      buttons.add(
        _actionButton(
          label: isZh ? '开始服务' : (isMs ? 'Mula Kerja' : 'Start Job'),
          // 👇 Icon 设为 null，改成橙色
          icon: null,
          color: _primaryOrange,
          onTap: () async {
            await _updateStatus(bookingId, 'In-Progress', isZh, isMs);
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    if (isInProgress) {
      buttons.add(
        _actionButton(
          label: isZh
              ? '标记为完成'
              : (isMs ? 'Tanda Selesai' : 'Mark as Completed'),
          icon: Icons.check_circle,
          color: _successGreen,
          onTap: () async {
            await _updateStatus(bookingId, 'Completed', isZh, isMs);
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
        ),
      );
    }

    if (buttons.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isZh
                    ? '没有可用的操作。'
                    : (isMs
                    ? 'Tiada tindakan tersedia untuk tempahan ini.'
                    : 'No action is available for this booking.'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: buttons
          .map(
            (b) => Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
      )
          .toList(),
    );
  }

  Widget _actionButton({
    required String label,
    IconData? icon, // 允许为 null
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
          icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
          label: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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

    // 如果没有 icon，就用普通按钮或者去掉 icon 属性的按钮
    if (icon == null) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 2,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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

  String _friendlyError(Object e) {
    final raw = e.toString();
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    if (raw.contains('Invalid service progress transition')) {
      return isZh
          ? '当前预约状态下不允许此操作。'
          : (isMs
          ? 'Tindakan ini tidak dibenarkan pada status tempahan semasa.'
          : 'This action is not allowed at the current booking status.');
    }
    if (raw.contains('Customer payment must succeed before service starts')) {
      return isZh
          ? '客户付款尚未完成，请稍候。'
          : (isMs
          ? 'Pembayaran pelanggan belum selesai. Sila tunggu.'
          : 'Customer payment has not been completed yet. Please wait.');
    }
    if (raw.contains('This service is not scheduled to start yet')) {
      return isZh
          ? '此服务尚未到预定开始时间，请在接近预约时间时重试。'
          : (isMs
          ? 'Perkhidmatan ini belum dijadualkan untuk bermula. Cuba lagi hampir dengan masa temu janji.'
          : 'This service is not scheduled to start yet. Try again closer to the appointment time.');
    }
    if (raw.contains('An active verified provider account is required')) {
      return isZh
          ? '您的服务商账户未验证或未激活。'
          : (isMs
          ? 'Akaun penyedia anda tidak disahkan atau tidak aktif.'
          : 'Your provider account is not verified or active.');
    }
    if (raw.contains('Booking not found')) {
      return isZh
          ? '找不到预约或不属于您。'
          : (isMs
          ? 'Tempahan tidak dijumpai atau bukan milik anda.'
          : 'Booking not found or does not belong to you.');
    }
    if (raw.contains('This booking request is no longer available')) {
      return isZh
          ? '此预约已无法修改。它已被接受或时间段已过。'
          : (isMs
          ? 'Tempahan ini tidak boleh diubah lagi. Ia telah diterima atau slot masa telah berlalu.'
          : 'This booking can no longer be modified. It has already been accepted or the time slot has passed.');
    }
    if (raw.contains('Explain why the requested slot cannot be accepted')) {
      return isZh
          ? '请提供有效的取消理由。'
          : (isMs
          ? 'Sila berikan alasan yang sah untuk pembatalan.'
          : 'Please provide a valid reason for cancellation.');
    }
    return raw
        .replaceAll('PostgrestException(message: ', '')
        .replaceAll(', code: ', ' (')
        .replaceAll(', details: , hint: null)', ')');
  }

  Future<void> _updateStatus(
      String bookingId, String newStatus, bool isZh, bool isMs) async {
    try {
      await _bookingService.updateStatus(bookingId, newStatus);

      if (newStatus == 'Completed') {
        final bookingRow = await _client
            .from('bookings')
            .select()
            .eq('booking_id', bookingId)
            .maybeSingle();

        if (bookingRow != null) {
          await _syncEarningsRecord(bookingRow);
        }
      }

      if (!mounted) return;
      _showAppDialog(
        title: isZh ? '成功' : (isMs ? 'Berjaya' : 'Success'),
        message: isZh
            ? '预约已标记为 $newStatus'
            : (isMs
            ? 'Tempahan ditanda sebagai $newStatus'
            : 'Booking marked as $newStatus'),
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: isZh ? '错误' : (isMs ? 'Ralat' : 'Error'),
        message: _friendlyError(e),
        isError: true,
      );
    }
  }

  Future<void> _cancelBooking(String bookingId, bool isZh, bool isMs) async {
    try {
      await _bookingService.cancel(bookingId, 'Cancelled by provider');

      if (!mounted) return;
      _showAppDialog(
        title: isZh ? '成功' : (isMs ? 'Berjaya' : 'Success'),
        message: isZh
            ? '预约已取消'
            : (isMs ? 'Tempahan dibatalkan' : 'Booking cancelled'),
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: isZh ? '错误' : (isMs ? 'Ralat' : 'Error'),
        message: _friendlyError(e),
        isError: true,
      );
    }
  }

  Future<void> _syncEarningsRecord(Map<String, dynamic> bookingRow) async {
    try {
      final bookingId = bookingRow['booking_id']?.toString();
      final providerId = bookingRow['provider_id']?.toString();
      final grossAmount =
          (bookingRow['total_amount'] as num?)?.toDouble() ?? 0.0;

      if (bookingId == null || providerId == null) return;

      final existing = await _client
          .from('provider_earnings')
          .select('earnings_id')
          .eq('booking_id', bookingId)
          .maybeSingle();

      if (existing != null) {
        return;
      }

      const platformFeePercent = 0.10;
      final platformFee = grossAmount * platformFeePercent;

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

  void _openChat(String bookingId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatInboxScreen(customer: false)),
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
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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

  Widget _statusChip(String status, bool isZh, bool isMs) {
    Color bg;
    Color fg;
    IconData icon;
    String displayText;

    switch (status.toLowerCase()) {
      case 'in-progress':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        icon = Icons.play_circle;
        displayText = isZh ? '进行中' : (isMs ? 'SEDANG BERJALAN' : 'IN-PROGRESS');
        break;
      case 'confirmed':
        bg = _lightOrange;
        fg = _primaryOrange;
        icon = Icons.verified;
        displayText = isZh ? '已确认' : (isMs ? 'DISAHKAN' : 'CONFIRMED');
        break;
      case 'pending':
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        icon = Icons.pending;
        displayText = isZh ? '待处理' : (isMs ? 'TERTUNDA' : 'PENDING');
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        icon = Icons.pending;
        displayText = status.toUpperCase();
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
            displayText,
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

  String _formatHeader(String dateKey) {
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    if (dateKey == 'Unscheduled') {
      return isZh ? '未排期' : (isMs ? 'Belum Dijadualkan' : 'Unscheduled');
    }
    try {
      final dt = DateTime.parse(dateKey);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(dt.year, dt.month, dt.day);
      final diff = target.difference(today).inDays;

      if (diff == 0) return isZh ? '今天' : (isMs ? 'Hari Ini' : 'Today');
      if (diff == 1) return isZh ? '明天' : (isMs ? 'Esok' : 'Tomorrow');

      return DateFormat.yMMMd().format(dt);
    } catch (_) {
      return dateKey;
    }
  }

  String _formatFullDateTime(String? raw) {
    if (raw == null) return '--';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat.yMMMd().add_Hm().format(dt);
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