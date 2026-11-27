import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import 'booking_detail_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final _service = BookingService();

  // 标签只有这 5 个
  final tabs = ['New', 'Confirmed', 'In-Progress', 'Completed', 'Cancelled'];

  // 映射到数据库的真实状态
  final statusMap = {
    'New': 'Pending',
    'Confirmed': 'Confirmed',
    'In-Progress': 'In-Progress',
    'Completed': 'Completed',
    'Cancelled': 'Cancelled',
  };

  int _tab = 0;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

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
    if (mounted) setState(() => _loading = true);
    try {
      final items = await _service.getMyBookings(status: statusMap[tabs[_tab]]);
      if (!mounted) return;

      // 过滤逻辑：如果单子时间已过，且状态不是 Completed / Cancelled，则直接隐藏
      final now = DateTime.now();
      final filteredItems = items.where((b) {
        final status = (b['booking_status'] ?? '').toString().toLowerCase();

        // 已完成和已取消的永远显示，不受时间限制
        if (status == 'completed' || status == 'cancelled') return true;

        final dateStr = b['scheduled_datetime']?.toString() ?? b['booking_date']?.toString();
        if (dateStr == null) return true;
        final dt = DateTime.tryParse(dateStr)?.toLocal();
        if (dt == null) return true;

        return dt.isAfter(now); // 未来的单子显示，过期的隐藏
      }).toList();

      setState(() {
        _items = filteredItems;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final lang = Localizations.localeOf(context).languageCode;
      _showAppDialog(
        title: lang == 'zh' ? '错误' : (lang == 'ms' ? 'Ralat' : 'Error'),
        message: lang == 'zh'
            ? '加载预约失败：$e'
            : (lang == 'ms' ? 'Gagal memuatkan tempahan: $e' : 'Failed to load bookings: $e'),
        isError: true,
      );
    }
  }

  // ============= 通用弹窗组件 (Pop-up Box) =============
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

  // 翻译 Tab 标题
  String _translateTab(String tab) {
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'zh') {
      if (tab == 'New') return '新订单';
      if (tab == 'Confirmed') return '已确认';
      if (tab == 'In-Progress') return '进行中';
      if (tab == 'Completed') return '已完成';
      if (tab == 'Cancelled') return '已取消';
    } else if (lang == 'ms') {
      if (tab == 'New') return 'Baharu';
      if (tab == 'Confirmed') return 'Disahkan';
      if (tab == 'In-Progress') return 'Sedang Berjalan';
      if (tab == 'Completed') return 'Selesai';
      if (tab == 'Cancelled') return 'Dibatalkan';
    }
    return tab;
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
          isZh ? '我的预约' : (isMs ? 'Tempahan Saya' : 'My Bookings'),
          // 👇 强制指定白色
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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ---- Status Filter Chips ----
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(tabs.length, (i) {
                    final selected = _tab == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _tab = i);
                          _load();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? _primaryOrange : _lightOrange,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? _primaryOrange : _borderOrange,
                            ),
                          ),
                          child: Text(
                            _translateTab(tabs[i]),
                            style: TextStyle(
                              color: selected ? Colors.white : _primaryOrange,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const Divider(height: 1),

            // ---- List ----
            Expanded(
              child: _loading
                  ? const Center(
                child: CircularProgressIndicator(color: _primaryOrange),
              )
                  : RefreshIndicator(
                onRefresh: _load,
                color: _primaryOrange,
                child: _items.isEmpty
                    ? _buildEmpty(isZh, isMs)
                    : ListView(
                  // 👇 添加了 BouncingScrollPhysics 实现拉到底部的弹性效果
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 120,
                  ),
                  children: _items
                      .map((b) => _bookingCard(b, isZh, isMs))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isZh, bool isMs) {
    return ListView(
      // 👇 无数据页面也加上弹性效果
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.event_busy_outlined, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        Center(
          child: Text(
            isZh ? '暂无预约' : (isMs ? 'Tiada tempahan' : 'No bookings'),
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            isZh
                ? '新的预约请求将显示在这里'
                : (isMs
                ? 'Permintaan tempahan baharu akan dipaparkan di sini'
                : 'New booking requests will appear here'),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _bookingCard(Map<String, dynamic> b, bool isZh, bool isMs) {
    final rawId = b['booking_id']?.toString() ?? '';
    final shortId = rawId.isEmpty
        ? 'N/A'
        : (rawId.length >= 8 ? rawId.substring(0, 8) : rawId);

    final cust =
        b['customer_profiles']?['users']?['full_name']?.toString() ??
            (isZh ? '客户' : (isMs ? 'Pelanggan' : 'Customer'));
    final svc = b['services']?['service_name']?.toString() ??
        (isZh ? '服务' : (isMs ? 'Perkhidmatan' : 'Service'));

    final amountRaw = b['total_amount'];
    final amountText = amountRaw == null
        ? '—'
        : (amountRaw is num
        ? amountRaw.toStringAsFixed(0)
        : amountRaw.toString());

    final status = b['booking_status']?.toString() ?? 'Pending';
    final date = b['booking_date']?.toString() ??
        (isZh ? '日期待定' : (isMs ? 'Tarikh TBD' : 'Date TBA'));

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: InkWell(
        onTap: () {
          if (rawId.isEmpty) {
            _showAppDialog(
              title: isZh ? '错误' : (isMs ? 'Ralat' : 'Error'),
              message: isZh
                  ? '预约 ID 缺失'
                  : (isMs ? 'ID Tempahan tiada' : 'Booking ID missing'),
              isError: true,
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookingDetailScreen(bookingId: rawId),
            ),
          ).then((_) => _load());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: ID + Amount
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _lightOrange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          color: _primaryOrange,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '#$shortId',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    amountRaw == null ? '—' : 'RM$amountText',
                    style: const TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Customer
              _infoRow(Icons.person_outline, cust),
              const SizedBox(height: 4),

              // Service
              _infoRow(Icons.build_outlined, svc),
              const SizedBox(height: 4),

              // Date
              _infoRow(Icons.calendar_today_outlined, date),
              const SizedBox(height: 12),

              // Status + View detail
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statusBadge(status, isZh, isMs),
                  Text(
                    isZh
                        ? '查看详情 →'
                        : (isMs ? 'Lihat butiran →' : 'View detail →'),
                    style: const TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status, bool isZh, bool isMs) {
    Color bg;
    Color fg;
    IconData icon;
    String displayStatus;

    switch (status.toLowerCase()) {
      case 'confirmed':
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF10B981);
        icon = Icons.check_circle_outline;
        displayStatus = isZh ? '已确认' : (isMs ? 'DISAHKAN' : 'CONFIRMED');
        break;
      case 'in-progress':
        bg = _lightOrange;
        fg = _primaryOrange;
        icon = Icons.timelapse;
        displayStatus = isZh ? '进行中' : (isMs ? 'SEDANG BERJALAN' : 'IN-PROGRESS');
        break;
      case 'completed':
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF6B7280);
        icon = Icons.done_all;
        displayStatus = isZh ? '已完成' : (isMs ? 'SELESAI' : 'COMPLETED');
        break;
      case 'cancelled':
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFEF4444);
        icon = Icons.cancel_outlined;
        displayStatus = isZh ? '已取消' : (isMs ? 'DIBATALKAN' : 'CANCELLED');
        break;
      default: // pending / new
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFF59E0B);
        icon = Icons.pending_outlined;
        displayStatus = isZh ? '新订单' : (isMs ? 'BAHARU' : 'NEW');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            displayStatus,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}