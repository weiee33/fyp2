import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import 'notification_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await _service.getMyNotifications();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: _items.map((n) {
                final read = n['is_read'] ?? false;
                return Card(
                  child: ListTile(
                    title: Text(n['title'] ?? '-',
                        style: TextStyle(
                            fontWeight: read
                                ? FontWeight.normal
                                : FontWeight.bold)),
                    subtitle: Text(n['message'] ?? ''),
                    trailing: read
                        ? null
                        : const Icon(Icons.circle,
                            size: 10, color: Colors.blue),
                    onTap: () async {
                      await _service.markAsRead(n['notification_id']);
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationDetailScreen(data: n),
                        ),
                      ).then((_) => _load());
                    },
                  ),
                );
              }).toList(),
            ),
    );
  }
}