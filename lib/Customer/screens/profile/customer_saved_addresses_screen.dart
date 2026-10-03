import 'package:flutter/material.dart';
import '../../services/customer_address_service.dart';
import '../home/add_address_map_screen.dart';

class CustomerSavedAddressesScreen extends StatefulWidget {
  const CustomerSavedAddressesScreen({super.key});
  @override
  State<CustomerSavedAddressesScreen> createState() =>
      _CustomerSavedAddressesScreenState();
}

class _CustomerSavedAddressesScreenState
    extends State<CustomerSavedAddressesScreen> {
  final _service = CustomerAddressService();
  late Future<List<Map<String, dynamic>>> _addresses;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _addresses = _service.getSavedAddresses();
  }

  Future<void> _reload() async {
    final future = _service.getSavedAddresses();
    setState(() => _addresses = future);
    try {
      await future;
    } catch (_) {
      /* The builder displays the failure. */
    }
  }

  Future<void> _change(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) await _reload();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update this address. Please retry.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved address?'),
        content: const Text(
          'Existing bookings keep their service address. If this is the default, another saved address becomes the default.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted)
      await _change(() => _service.deleteAddress(row['address_id'].toString()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved Addresses')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy
          ? null
          : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddAddressMapScreen()),
              );
              if (mounted) await _reload();
            },
      icon: const Icon(Icons.add),
      label: const Text('Add address'),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _addresses,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your saved addresses.'),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        final rows = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Add a service address before booking.'),
                ),
              ...rows.map((row) {
                final address = ['address_line', 'city', 'state', 'postcode']
                    .map((key) => row[key]?.toString() ?? '')
                    .where((part) => part.isNotEmpty)
                    .join(', ');
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['label']?.toString() ?? 'Address',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(address),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (row['is_default'] == true)
                              const Chip(label: Text('Default'))
                            else
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _change(
                                        () => _service.setDefaultAddress(
                                          row['address_id'].toString(),
                                          address,
                                        ),
                                      ),
                                child: const Text('Set as default'),
                              ),
                            TextButton(
                              onPressed: _busy ? null : () => _delete(row),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    ),
  );
}
