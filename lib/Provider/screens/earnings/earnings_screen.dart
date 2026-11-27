import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:fyp2/Provider/services/earnings_service.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final _service = EarningsService();
  List<Map<String, dynamic>> _rows = [];
  Map<String, double> _sum = {};
  bool _loading = true;

  int _chartView = 0;

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _bgWhite = Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _service.getAllEarnings();
      final sum = _service.summarize(rows);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _sum = sum;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '加载收益失败：$e'
                : (Localizations.localeOf(context).languageCode == 'ms'
                ? 'Gagal memuatkan pendapatan: $e'
                : 'Failed to load earnings: $e'),
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  DateTime? _parseDate(Map<String, dynamic> row) {
    final dateStr =
        row['earned_at']?.toString() ??
            row['bookings']?['booking_date']?.toString() ??
            row['booking_date']?.toString() ??
            row['date']?.toString() ??
            row['created_at']?.toString();
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  double _amount(Map<String, dynamic> row) {
    return (row['net_earnings'] ?? row['amount'] ?? row['total_amount'] ?? 0)
        .toDouble();
  }

  List<double> _getWeekDaysData() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final result = List<double>.filled(7, 0);

    for (final row in _rows) {
      final parsed = _parseDate(row);
      if (parsed == null) continue;
      final rowDate = DateTime(parsed.year, parsed.month, parsed.day);
      final diff = rowDate.difference(monday).inDays;
      if (diff >= 0 && diff < 7) {
        result[diff] += _amount(row);
      }
    }
    return result;
  }

  List<String> _getWeekDaysLabels() {
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  }

  List<double> _getMonthlyData() {
    final now = DateTime.now();
    final result = List<double>.filled(12, 0);

    for (final row in _rows) {
      final parsed = _parseDate(row);
      if (parsed == null) continue;
      if (parsed.year == now.year) {
        final monthIndex = parsed.month - 1;
        if (monthIndex >= 0 && monthIndex < 12) {
          result[monthIndex] += _amount(row);
        }
      }
    }
    return result;
  }

  List<String> _getMonthlyLabels() {
    return const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
  }

  List<double> _getYearlyData() {
    final years = [2026, 2027, 2028, 2029, 2030];
    final result = List<double>.filled(5, 0);

    for (final row in _rows) {
      final parsed = _parseDate(row);
      if (parsed == null) continue;
      final idx = years.indexOf(parsed.year);
      if (idx >= 0) result[idx] += _amount(row);
    }
    return result;
  }

  List<String> _getYearlyLabels() {
    return ['2026', '2027', '2028', '2029', '2030'];
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bgWhite,
        body: Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
      );
    }

    final today = _sum['today'] ?? 0;
    final week = _sum['week'] ?? 0;
    final month = _sum['month'] ?? 0;
    final pending = _sum['pending'] ?? 0;

    List<double> chartValues;
    List<String> chartLabels;
    String chartSubtitle;

    switch (_chartView) {
      case 1:
        chartValues = _getMonthlyData();
        chartLabels = _getMonthlyLabels();
        chartSubtitle = 'This Year (Monthly)';
        break;
      case 2:
        chartValues = _getYearlyData();
        chartLabels = _getYearlyLabels();
        chartSubtitle = 'Years (2026 - 2030)';
        break;
      default:
        chartValues = _getWeekDaysData();
        chartLabels = _getWeekDaysLabels();
        chartSubtitle = 'This Week (Mon - Sun)';
    }

    final hasData = chartValues.any((v) => v > 0);
    final maxY = hasData
        ? chartValues.reduce((a, b) => a > b ? a : b) * 1.2
        : 10.0;

    final lang = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: _bgWhite,
      // 👇 AppBar 修改为橙色背景，白色文字，并去掉了 action 按钮
      appBar: AppBar(
        title: Text(
          lang == 'zh' ? '收益' : (lang == 'ms' ? 'Pendapatan' : 'Earnings'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white, // 👈 强制标题为白色
          ),
        ),
        backgroundColor: _primaryOrange, // 👈 修改为橙色背景
        foregroundColor: Colors.white,  // 👈 箭头和图标改为白色
        elevation: 0,
        automaticallyImplyLeading: true,
        // 👈 删除了 actions 里面的 IconButton
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryOrange,
          child: ListView(
            // 👇 添加了 BouncingScrollPhysics 实现拉到底部的弹性效果
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              const SizedBox(height: 8), // 稍微加一点间距
              // ===== Hero Card =====
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryOrange, Color(0xFFFF8C42)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryOrange.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          lang == 'zh'
                              ? '总余额'
                              : (lang == 'ms' ? 'Jumlah Baki' : 'Total Balance'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Icon(Icons.account_balance_wallet_outlined,
                            color: Colors.white70),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "RM${month.toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              lang == 'zh'
                                  ? '本月'
                                  : (lang == 'ms' ? 'Bulan Ini' : 'This Month'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _miniStat(
                          lang == 'zh'
                              ? '今日'
                              : (lang == 'ms' ? 'Hari Ini' : 'Today'),
                          "RM${today.toStringAsFixed(0)}",
                          Icons.today,
                        ),
                        Container(
                            width: 1,
                            height: 24,
                            color: Colors.white.withValues(alpha: 0.3)),
                        _miniStat(
                          lang == 'zh'
                              ? '本周'
                              : (lang == 'ms' ? 'Minggu Ini' : 'This Week'),
                          "RM${week.toStringAsFixed(0)}",
                          Icons.date_range,
                        ),
                        Container(
                            width: 1,
                            height: 24,
                            color: Colors.white.withValues(alpha: 0.3)),
                        _miniStat(
                          lang == 'zh'
                              ? '待处理'
                              : (lang == 'ms' ? 'Tertunda' : 'Pending'),
                          "RM${pending.toStringAsFixed(0)}",
                          Icons.hourglass_empty,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ===== Chart Card =====
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lang == 'zh'
                                ? '收益趋势'
                                : (lang == 'ms'
                                ? 'Trend Pendapatan'
                                : 'Earnings Trend'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          _buildToggle(),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chartSubtitle,
                        style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: hasData
                            ? LineChart(
                          LineChartData(
                            maxY: maxY,
                            minY: 0,
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    return LineTooltipItem(
                                      'RM ${spot.y.toStringAsFixed(0)}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxY > 4 ? (maxY / 4) : 1,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: Colors.grey.shade100,
                                strokeWidth: 1,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              topTitles: const AxisTitles(
                                  sideTitles:
                                  SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles:
                                  SideTitles(showTitles: false)),
                              leftTitles: const AxisTitles(
                                  sideTitles:
                                  SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: 1.0,
                                  getTitlesWidget: (value, meta) {
                                    if (value % 1 != 0) {
                                      return const SizedBox.shrink();
                                    }
                                    final idx = value.toInt();
                                    if (idx < 0 ||
                                        idx >= chartLabels.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding:
                                      const EdgeInsets.only(top: 8),
                                      child: Text(
                                        chartLabels[idx],
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: List.generate(
                                    chartValues.length,
                                        (i) => FlSpot(
                                        i.toDouble(), chartValues[i])),
                                isCurved: true,
                                color: _primaryOrange,
                                barWidth: 4,
                                isStrokeCapRound: true,
                                dotData:
                                const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      _primaryOrange.withValues(
                                          alpha: 0.3),
                                      _primaryOrange.withValues(
                                          alpha: 0.0),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                            : Center(
                          child: Text(
                            lang == 'zh'
                                ? '暂无收益数据'
                                : (lang == 'ms'
                                ? 'Tiada data pendapatan lagi'
                                : 'No earnings data yet'),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ===== Recent Transactions =====
              Text(
                lang == 'zh'
                    ? '最近交易'
                    : (lang == 'ms' ? 'Transaksi Terkini' : 'Recent Transactions'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              if (_rows.isEmpty)
                _buildEmptyState()
              else
                ..._rows.take(15).map((row) => _buildTransactionItem(row)),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildToggle() {
    final lang = Localizations.localeOf(context).languageCode;
    return Container(
      decoration: BoxDecoration(
        color: _lightOrange,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(
              lang == 'zh' ? '每周' : (lang == 'ms' ? 'Mingguan' : 'Weekly'), 0),
          _toggleBtn(
              lang == 'zh' ? '每月' : (lang == 'ms' ? 'Bulanan' : 'Monthly'), 1),
          _toggleBtn(
              lang == 'zh' ? '每年' : (lang == 'ms' ? 'Tahunan' : 'Yearly'), 2),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, int value) {
    final selected = _chartView == value;
    return GestureDetector(
      onTap: () => setState(() => _chartView = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _primaryOrange : Colors.grey.shade600,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> row) {
    final date = _parseDate(row);
    final dateStr = date != null ? '${date.day} ${_monthName(date.month)}' : '';
    final amount = _amount(row);
    final isPending =
        row['payment_status'] == 'Pending' || row['status'] == 'Pending';

    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final serviceName = row['service_name']?.toString() ??
        (isZh ? '服务付款' : (isMs ? 'Bayaran Perkhidmatan' : 'Service Payment'));
    final customerName = row['customer_name']?.toString() ??
        (isZh ? '客户' : (isMs ? 'Pelanggan' : 'Customer'));

    final borderColors = [
      Colors.blue.shade300,
      Colors.purple.shade300,
      Colors.orange.shade300,
      Colors.pink.shade300,
      Colors.green.shade300
    ];
    final colorIndex = serviceName.hashCode % borderColors.length;
    final borderColor = borderColors[colorIndex.abs()];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _lightOrange,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
            const Icon(Icons.work_outline, color: _primaryOrange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$customerName · $dateStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RM${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                  isPending ? Colors.orange.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isPending
                      ? (isZh ? '待处理' : (isMs ? 'Tertunda' : 'Pending'))
                      : (isZh ? '已支付' : (isMs ? 'Dibayar' : 'Paid')),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isPending
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Widget _buildEmptyState() {
    final lang = Localizations.localeOf(context).languageCode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              lang == 'zh'
                  ? '暂无交易'
                  : (lang == 'ms' ? 'Tiada transaksi lagi' : 'No transactions yet'),
              style: TextStyle(
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}