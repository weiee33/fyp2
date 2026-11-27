import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import '../../services/profile_service.dart';

class WorkingHoursScreen extends StatefulWidget {
  const WorkingHoursScreen({super.key});
  @override
  State<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends State<WorkingHoursScreen> {
  final _service = ProfileService();
  final days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final Map<int, bool> _on = {for (var i = 0; i < 7; i++) i: true};
  final Map<int, TimeOfDay> _start = {
    for (var i = 0; i < 7; i++) i: const TimeOfDay(hour: 9, minute: 0),
  };
  final Map<int, TimeOfDay> _end = {
    for (var i = 0; i < 7; i++) i: const TimeOfDay(hour: 18, minute: 0),
  };
  bool _loading = true;
  bool _saving = false;

  // 🎨 Unified Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.getWorkingHours();
      for (final r in rows) {
        final i = (r['day_of_week'] as num).toInt();
        _on[i] = r['is_active'] ?? true;
        _start[i] = _parseTime(r['start_time']);
        _end[i] = _parseTime(r['end_time']);
      }
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: 'Error',
        message: "Failed to load working hours: $e",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay _parseTime(dynamic t) {
    if (t == null) return const TimeOfDay(hour: 9, minute: 0);
    final parts = t.toString().split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  Future<void> _pick(int day, bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _start[day]! : _end[day]!,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryOrange,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (t == null) return;
    setState(() {
      if (isStart) {
        _start[day] = t;
      } else {
        _end[day] = t;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final rows = List.generate(7, (i) {
        return {
          'day_of_week': i,
          'is_active': _on[i],
          'start_time':
          '${_start[i]!.hour.toString().padLeft(2, '0')}:${_start[i]!.minute.toString().padLeft(2, '0')}:00',
          'end_time':
          '${_end[i]!.hour.toString().padLeft(2, '0')}:${_end[i]!.minute.toString().padLeft(2, '0')}:00',
        };
      });

      await _service.setWorkingHours(rows);

      if (!mounted) return;

      _showAppDialog(
        title: 'Success',
        message: 'Working hours saved.',
        isError: false,
      );

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showAppDialog(
        title: 'Error',
        message: "Save failed: $e",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============= Pop-up Box 弹窗 =============
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

  String _translateDay(String day, bool isZh, bool isMs) {
    if (isZh) {
      switch (day) {
        case 'Monday': return '星期一';
        case 'Tuesday': return '星期二';
        case 'Wednesday': return '星期三';
        case 'Thursday': return '星期四';
        case 'Friday': return '星期五';
        case 'Saturday': return '星期六';
        case 'Sunday': return '星期日';
      }
    } else if (isMs) {
      switch (day) {
        case 'Monday': return 'Isnin';
        case 'Tuesday': return 'Selasa';
        case 'Wednesday': return 'Rabu';
        case 'Thursday': return 'Khamis';
        case 'Friday': return 'Jumaat';
        case 'Saturday': return 'Sabtu';
        case 'Sunday': return 'Ahad';
      }
    }
    return day;
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
        // 👇 强制 AppBar 标题为白色
        title: Text(
          isZh ? '工作时间' : (isMs ? 'Waktu Bekerja' : 'Working Hours'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(color: _primaryOrange),
      )
          : SafeArea(
        child: ListView(
          // 👇 添加 BouncingScrollPhysics 实现弹性效果
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          children: [
            ...List.generate(
              7,
                  (i) => Card(
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _translateDay(days[i], isZh, isMs),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF111827),
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _on[i]!
                                    ? (isZh ? '开启' : (isMs ? 'BUKA' : 'ON'))
                                    : (isZh ? '关闭' : (isMs ? 'TUTUP' : 'OFF')),
                                style: TextStyle(
                                  color: _on[i]!
                                      ? _primaryOrange
                                      : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Switch(
                                value: _on[i]!,
                                activeThumbColor: _primaryOrange,
                                onChanged: (v) =>
                                    setState(() => _on[i] = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _on[i]!
                                  ? () => _pick(i, true)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _primaryOrange,
                                side: const BorderSide(
                                  color: _primaryOrange,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding:
                                const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(_start[i]!.format(context)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _on[i]!
                                  ? () => _pick(i, false)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _primaryOrange,
                                side: const BorderSide(
                                  color: _primaryOrange,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding:
                                const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(_end[i]!.format(context)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _saving
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
                    : Text(
                  isZh ? '保存' : (isMs ? 'Simpan' : 'Save'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}