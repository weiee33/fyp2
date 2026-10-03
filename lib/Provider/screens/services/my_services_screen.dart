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
      final items = await _service.getMyServices();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load services: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service'),
        content: const Text('Are you sure you want to delete this service?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteService(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Service deleted'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My Services'),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryOrange,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Add New Service Button ----
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EditServiceScreen()),
                  ).then((_) => _load()),
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Add New Service',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Empty State ----
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.work_off_outlined,
                        size: 56,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No services yet',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tap "Add New Service" to create your first listing',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
              // ---- Service List ----
                ..._items.map((s) => _serviceCard(s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> s) {
    final name = s['service_name']?.toString() ?? 'Service';
    final price = s['base_price']?.toString() ?? '0';
    final duration = s['estimated_duration']?.toString() ?? '60';
    final pricing = s['pricing_type']?.toString() ?? 'Fixed';

    return Card(
      elevation: 1,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _lightOrange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.build_outlined,
                color: _primaryOrange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RM$price · $duration min · $pricing',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: _primaryOrange),
              tooltip: 'Edit',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EditServiceScreen(existing: s)),
              ).then((_) => _load()),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () => _delete(s['service_id'].toString()),
            ),
          ],
        ),
      ),
    );
  }
}