import 'package:flutter/material.dart';

import '../../../shared/localization/app_language.dart';
import '../../services/support_service.dart';
import '../../widgets/support_card.dart';
import '../support/support_screen.dart';

class HelpCentreScreen extends StatefulWidget {
  final ProviderSupportService? service;
  const HelpCentreScreen({super.key, this.service});
  @override
  State<HelpCentreScreen> createState() => _HelpCentreScreenState();
}

class _HelpCentreScreenState extends State<HelpCentreScreen> {
  late final _service = widget.service ?? ProviderSupportService();
  final _requests = <Map<String, dynamic>>[];
  bool _loading = false, _more = false;
  String? _error;

  static const _primaryOrange = Color(0xFFFF6B00);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.requests(offset: more ? _requests.length : 0);
      if (mounted) {
        setState(() {
          if (!more) _requests.clear();
          _requests.addAll(rows);
          _more = rows.length == 30;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compose() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderSupportComposeScreen(service: _service),
      ),
    );
    if (!mounted || id == null) return;
    await _load();
    if (mounted) await _open(id);
  }

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderSupportDetailScreen(id: id, service: _service),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: Text(tr('Help Centre')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ProviderSupportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.support_agent_rounded, color: _primaryOrange, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    tr('How can we help?'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('Ask a question, share feedback or make a complaint.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _primaryOrange, foregroundColor: Colors.white),
                    onPressed: _compose,
                    child: Text(tr('Contact Admin')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(tr('Before you send'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ProviderSupportCard(
              child: Column(
                children: [
                  _HelpTopic(
                    title: tr('Booking and payout help'),
                    body: tr('Open Booking Details to contact your customer or request support linked to that booking.'),
                  ),
                  const Divider(),
                  _HelpTopic(
                    title: tr('Account and privacy help'),
                    body: tr('Use Profile to update your business details, services, service areas and working hours.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(tr('Your support requests'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_error != null)
              ProviderSupportCard(
                child: Column(
                  children: [
                    Text(tr(_error!)),
                    TextButton(onPressed: _load, child: Text(tr('Retry'))),
                  ],
                ),
              ),
            if (_requests.isEmpty && !_loading && _error == null)
              ProviderSupportCard(
                child: Text(tr('No support requests yet. Your messages and support responses will appear here.')),
              ),
            for (final row in _requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ProviderSupportCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['subject'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${tr(row['booking_id'] == null ? 'General enquiry' : 'Booking support')}\n${tr(row['status'] as String)} · ${formatSupportDate(row['created_at'])}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(row['id'] as String),
                  ),
                ),
              ),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: _primaryOrange))),
            if (_more && !_loading)
              TextButton(onPressed: () => _load(more: true), child: Text(tr('Load more'))),
            const SizedBox(height: 16),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}

class _HelpTopic extends StatelessWidget {
  final String title, body;
  const _HelpTopic({required this.title, required this.body});
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    shape: const Border(),
    collapsedShape: const Border(),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    children: [Text(body)],
  );
}