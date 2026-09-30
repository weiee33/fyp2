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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _service.getWorkingHours();
    for (final r in rows) {
      final i = (r['day_of_week'] as num).toInt();
      _on[i] = r['is_active'] ?? true;
      _start[i] = _parseTime(r['start_time']);
      _end[i] = _parseTime(r['end_time']);
    }
    if (mounted) setState(() => _loading = false);
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
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Working Hours')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...List.generate(
                  7,
                  (i) => Card(
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
                              Switch(
                                value: _on[i]!,
                                onChanged: (v) => setState(() => _on[i] = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _pick(i, true),
                                  child: Text(_start[i]!.format(context)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _pick(i, false),
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
                ElevatedButton(
                    onPressed: _save, child: const Text('Save')),
              ],
            ),
    );
  }
}