import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Provider/screens/home/provider_floating_nav_bar.dart';

class AiScheduleScreen extends StatefulWidget {
  const AiScheduleScreen({super.key});

  @override
  State<AiScheduleScreen> createState() => _AiScheduleScreenState();
}

class _AiScheduleScreenState extends State<AiScheduleScreen> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _schedule = [];
  double _totalDistanceKm = 0;
  int _totalTravelMin = 0;
  double _estimatedEarnings = 0;
  bool _loading = true;
  String? _error;

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
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() { _schedule = []; _loading = false; });
        return;
      }

      final providerRow = await _client
          .from('provider_profiles')
          .select('provider_id')
          .eq('user_id', uid)
          .maybeSingle();

      final providerId = providerRow?['provider_id']?.toString();
      if (providerId == null) {
        if (mounted) setState(() { _schedule = []; _loading = false; });
        return;
      }

      final now = DateTime.now().toUtc().toIso8601String();

      // 👇 关键修复：在这里加入 Join 查询
      // 假设你的 bookings 表有 customer_id 和 service_id 关联
      final res = await _client
          .from('bookings')
          .select('*, customer_profiles!inner(users(full_name)), services!bookings_service_id_fkey(service_name)')
          .eq('provider_id', providerId)
          .not('booking_status', 'in', '(Cancelled,Completed)')
          .gte('scheduled_datetime', now)
          .order('scheduled_datetime', ascending: true);

      final bookings = List<Map<String, dynamic>>.from(res);

      if (bookings.isEmpty) {
        if (mounted) setState(() { _schedule = []; _loading = false; });
        return;
      }

      final jobs = bookings.map((b) => {
        'booking_id': b['booking_id'],
        'address': b['customer_address'] ?? 'Unknown Address',
        'coordinates': b['customer_coordinates'] ?? '',
        'estimated_duration': b['duration_minutes'] ?? 60,
        'total_amount': b['total_amount'] ?? 0,
      }).toList();

      final response = await _client.functions.invoke(
        'provider-ai-smart-schedule',
        body: { 'bookings': jobs },
      );

      if (!mounted) return;

      final dynamic responseData = response.data;
      Map<String, dynamic> data;

      if (responseData is String) {
        data = jsonDecode(responseData);
      } else {
        data = responseData as Map<String, dynamic>;
      }

      final List<dynamic> aiSchedule = data['schedule'] ?? [];
      final List<Map<String, dynamic>> finalSchedule = [];

      for (final step in aiSchedule) {
        final bId = step['booking_id'];
        final originalBooking = bookings.firstWhere(
              (b) => b['booking_id'] == bId,
          orElse: () => {},
        );

        if (originalBooking.isNotEmpty) {
          final travelDist = double.tryParse(step['travelDistanceFromPrevious']?.toString() ?? '0') ?? 0.0;
          final travelTime = int.tryParse(step['travelTimeFromPrevious']?.toString() ?? '0') ?? 0;
          final stepNum = int.tryParse(step['step']?.toString() ?? '1') ?? 1;

          finalSchedule.add({
            ...originalBooking,
            'ai_travel_distance': travelDist,
            'ai_travel_time': travelTime,
            'ai_step': stepNum,
          });
        }
      }

      double earnings = finalSchedule.fold(0, (sum, b) => sum + ((b['total_amount'] as num?)?.toDouble() ?? 0));

      setState(() {
        _schedule = finalSchedule;
        _totalDistanceKm = (data['totalDistance'] as num?)?.toDouble() ?? 0;
        _totalTravelMin = (data['totalTravel'] as num?)?.toInt() ?? 0;
        _estimatedEarnings = earnings;
        _loading = false;
      });

    } catch (e) {
      if (!mounted) return;
      debugPrint("AI Schedule error: $e");
      setState(() {
        _loading = false;
        _error = "AI failed to plan your route. Please try again.";
      });
    }
  }

  String _formatTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return tr("{0}m", [m]);
    return tr("{0}h {1}m", [h, m]);
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      appBar: AppBar(
        title: Text(
          tr('AI Smart Schedule'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _primaryOrange))
                : SafeArea(
              child: RefreshIndicator(
                onRefresh: _load,
                color: _primaryOrange,
                child: _error != null
                    ? _errorState(isZh, isMs)
                    : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _primaryOrange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today, size: 11, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                DateFormat.yMMMd().format(DateTime.now()),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        _statCard(
                          label: isZh ? '总单数' : (isMs ? 'Jumlah Kerja' : 'Total Jobs'),
                          value: '${_schedule.length}',
                          icon: Icons.work_outline,
                          color: _primaryOrange,
                        ),
                        const SizedBox(width: 10),
                        _statCard(
                          label: isZh ? '总距离' : (isMs ? 'Jumlah Jarak' : 'Total Distance'),
                          value: tr("{0} km", [_totalDistanceKm.toStringAsFixed(1)]),
                          icon: Icons.route_outlined,
                          color: _successGreen,
                        ),
                        const SizedBox(width: 10),
                        _statCard(
                          label: isZh ? '行程时间' : (isMs ? 'Masa Perjalanan' : 'Travel Time'),
                          value: _formatTime(_totalTravelMin),
                          icon: Icons.timer_outlined,
                          color: const Color(0xFF8B5CF6),
                        ),
                        const SizedBox(width: 10),
                        _statCard(
                          label: isZh ? '预计收入' : (isMs ? 'Anggaran Pendapatan' : 'Est. Earnings'),
                          value: tr("RM{0}", [_estimatedEarnings.toStringAsFixed(0)]),
                          icon: Icons.attach_money,
                          color: const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _primaryOrange,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.route, size: 18, color: _primaryOrange),
                        const SizedBox(width: 6),
                        Text(
                          isZh ? '优化路线' : (isMs ? 'Laluan Dioptimumkan' : 'Optimized Route'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_schedule.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            tr('No confirmed bookings today'),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ..._schedule.map((b) => _scheduleTile(b, isZh, isMs)),
                  ],
                ),
              ),
            ),
          ),

          ProviderFloatingNavBar(
            currentIndex: 3,
            onTabChanged: (index) => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _errorState(bool isZh, bool isMs) {
    return ListView(
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
            child: Icon(Icons.error_outline, size: 56, color: Colors.red.shade400),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            isZh
                ? 'AI 无法规划您的路线，请重试。'
                : (isMs
                ? 'AI gagal merancang laluan anda. Sila cuba lagi.'
                : 'AI failed to plan your route. Please try again.'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(tr('Retry')),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scheduleTile(Map<String, dynamic> b, bool isZh, bool isMs) {
    final step = b['ai_step'] as int? ?? 1;
    final travelDist = (b['ai_travel_distance'] as num?)?.toDouble() ?? 0;
    final travelTime = (b['ai_travel_time'] as num?)?.toInt() ?? 0;

    // 👇 从 Join 的数据里提取真实客户名和服务名
    final cust = b['customer_profiles']?['users']?['full_name']?.toString() ?? tr('Customer');
    final svc = b['services']?['service_name']?.toString() ?? tr('Service');

    final address = b['customer_address']?.toString() ?? tr('Address');
    final duration = (b['duration_minutes'] as num?)?.toInt() ?? 60;
    final amount = (b['total_amount'] as num?)?.toDouble() ?? 0;

    // 格式化时间（如果你有 scheduled_datetime 可以替换这里的 step）
    final scheduledAt = b['scheduled_datetime']?.toString();
    String timeStr = 'Step $step';
    if (scheduledAt != null) {
      final dt = DateTime.tryParse(scheduledAt)?.toLocal();
      if (dt != null) {
        timeStr = DateFormat('HH:mm').format(dt); // 像图2一样显示具体时间
      }
    }

    return Card(
      elevation: 1,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step > 1 && travelDist > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: _lightOrange,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderOrange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_car, size: 14, color: _primaryOrange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isZh
                            ? '行驶 ${travelDist.toStringAsFixed(1)} 公里（距上一单 $travelTime 分钟）'
                            : (isMs
                            ? 'Pandu ${travelDist.toStringAsFixed(1)} km ($travelTime min dari sebelumnya)'
                            : 'Drive ${travelDist.toStringAsFixed(1)} km ($travelTime min from previous)'),
                        style: const TextStyle(fontSize: 11, color: _primaryOrange, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 👇 左侧的时间/步骤卡片，更像图2的设计
                Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: _lightOrange,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _borderOrange),
                  ),
                  child: Column(
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _primaryOrange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr("{0}m", [duration]),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              svc, // 服务名称
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 添加一个跟图2一样的 CONFIRMED 标签
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tr('CONFIRMED'),
                              style: TextStyle(color: Colors.blue.shade700, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cust, // 客户名字
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            tr("RM{0}", [amount.toStringAsFixed(2)]),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryOrange),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}