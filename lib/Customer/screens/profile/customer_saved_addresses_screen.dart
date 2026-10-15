import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/customer_refresh.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import '../../services/customer_address_service.dart';
import '../home/add_address_map_screen.dart';

class CustomerSavedAddressesScreen extends StatefulWidget {
  final CustomerAddressService? service;
  const CustomerSavedAddressesScreen({super.key, this.service});
  @override
  State<CustomerSavedAddressesScreen> createState() =>
      _CustomerSavedAddressesScreenState();
}

class _CustomerSavedAddressesScreenState
    extends State<CustomerSavedAddressesScreen> {
  late final _service = widget.service ?? CustomerAddressService();
  late Future<List<Map<String, dynamic>>> _addresses;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _addresses = _fetchRows();
  }

  Future<List<Map<String, dynamic>>> _fetchRows() async {
    try {
      return await _service.getSavedAddresses();
    } catch (e) {
      if (mounted) CustomerDialogs.error(context, e);
      rethrow;
    }
  }

  Future<void> _reload() async {
    final future = _fetchRows();
    setState(() {
      _addresses = future;
    });
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
      if (mounted) {
        setState(() => _busy = false);
        await CustomerDialogs.show(
          context,
          message: tr('Address updated successfully.'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await CustomerDialogs.error(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete saved address?')),
        content: Text(
          tr(
            'Existing bookings keep their service address. If this is the default, another saved address becomes the default.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted)
      await _change(() => _service.deleteAddress(row['address_id'].toString()));
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Saved Addresses'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddAddressMapScreen(),
                  ),
                );
                if (mounted) await _reload();
              },
        icon: const Icon(Icons.add),
        label: Text(tr('Add address')),
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
                  Text(tr('Could not load your saved addresses.')),
                  TextButton(onPressed: _reload, child: Text(tr('Retry'))),
                ],
              ),
            );
          final rows = snapshot.data ?? [];
          return CustomerRefresh(
            onRefresh: _reload,
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (rows.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(tr('Add a service address before booking.')),
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
                            tr(row['label']?.toString() ?? 'Address'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(address),
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (row['is_default'] == true)
                                Chip(label: Text(tr('Default')))
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
                                  child: Text(tr('Set as default')),
                                ),
                              TextButton(
                                onPressed: _busy ? null : () => _delete(row),
                                child: Text(tr('Delete')),
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
}
