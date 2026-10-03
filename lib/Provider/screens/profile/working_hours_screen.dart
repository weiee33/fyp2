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
    'Sunday'
  ];
  final Map<int, bool> _on = {for (var i = 0; i < 7; i++) i: true};
  final Map<int, TimeOfDay> _start = {
    for (var i = 0; i < 7; i++) i: const TimeOfDay(hour: 9, minute: 0)
  };
  final Map<int, TimeOfDay> _end = {
    for (var i = 0; i < 7; i++) i: const TimeOfDay(hour: 18, minute: 0)
  };
  bool _loading = true;
  bool _saving = false;

  static const _primaryColor = Color(0xFF1E3A8A);

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
      _showError('Failed to load working hours: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay _parseTime(dynamic t) {
    if (t == null) return const TimeOfDay(hour: 9, minute: 0);
    final parts = t.toString().split(':');
    return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts[1]) ?? 0);
  }

  Future<void> _pick(int day, bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _start[day]! : _end[day]!,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Working hours saved'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Working Hours'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...List.generate(
              7,
                  (i) => Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(days[i],
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Text(
                                _on[i]! ? 'ON' : 'OFF',
                                style: TextStyle(
                                  color: _on[i]!
                                      ? Colors.green.shade700
                                      : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Switch(
                                value: _on[i]!,
                                activeThumbColor: _primaryColor,
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
                              child: Text(_start[i]!.format(context)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _on[i]!
                                  ? () => _pick(i, false)
                                  : null,
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
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                    : const Text(
                  'Save',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
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