import 'package:flutter/material.dart';
import '../../services/service_service.dart';
import 'edit_service_screen.dart';

class MyServicesScreen extends StatefulWidget {
  const MyServicesScreen({super.key});
  @override
  State<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends State<MyServicesScreen> {
  final _service = ServiceService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await _service.getMyServices();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Services')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const EditServiceScreen()),
            ).then((_) => _load()),
            icon: const Icon(Icons.add),
            label: const Text('Add New Service'),
          ),
          const SizedBox(height: 12),
          ..._items.map((s) => Card(
            child: ListTile(
              title: Text(s['service_name'] ?? '-'),
              subtitle: Text(
                  'RM${s['base_price']} · ${s['estimated_duration']} min'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              EditServiceScreen(existing: s)),
                    ).then((_) => _load()),
                    child: const Text('Edit'),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () async {
                      await _service
                          .deleteService(s['service_id']);
                      _load();
                    },
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }
}