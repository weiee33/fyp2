import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/localization/app_language.dart';
import '../../services/support_service.dart';
import '../../widgets/support_card.dart';
import '../../widgets/support_photo.dart';

class ProviderSupportScreen extends StatefulWidget {
  final ProviderSupportService? service;
  const ProviderSupportScreen({super.key, this.service});
  @override
  State<ProviderSupportScreen> createState() => _ProviderSupportState();
}

class _ProviderSupportState extends State<ProviderSupportScreen> {
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
      if (mounted) setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMessage(Object e) {
    if (e is String) return e;
    return e.toString().replaceFirst('Exception: ', '');
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
                      '${tr(row['subject'] == null ? 'General enquiry' : 'Booking support')}\n${tr(row['status'] as String)} · ${formatSupportDate(row['created_at'])}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    // 修改 1：把 dispute_id 改成 id
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

class ProviderSupportComposeScreen extends StatefulWidget {
  final String? bookingId;
  final ProviderSupportService? service;
  final Future<XFile?> Function(ImageSource)? pickPhoto;
  const ProviderSupportComposeScreen({
    super.key,
    this.bookingId,
    this.service,
    this.pickPhoto,
  });
  @override
  State<ProviderSupportComposeScreen> createState() => _ProviderComposeState();
}

class _ProviderComposeState extends State<ProviderSupportComposeScreen> {
  static const _primaryOrange = Color(0xFFFF6B00);
  late final _service = widget.service ?? ProviderSupportService();

  final _requestId = DateTime.now().millisecondsSinceEpoch.toString() +
      Random().nextInt(99999).toString().padLeft(5, '0');

  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController(), _description = TextEditingController();
  final _photos = <ProviderSupportPhoto>[];
  bool _sending = false, _locked = false, _picking = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_picking || _locked || _photos.length >= 3) return;
    setState(() => _picking = true);
    try {
      final file = await (widget.pickPhoto?.call(source) ?? ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85));
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) throw const FormatException('Choose a photo smaller than 5 MB.');

      final photo = ProviderSupportPhoto(await file.readAsBytes());
      try {
        final codec = await ui.instantiateImageCodec(photo.bytes, targetWidth: 100);
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } catch (_) {
        throw const FormatException('This photo could not be read. Choose another photo.');
      }
      if (mounted) {
        setState(() {
          _photos.add(photo);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String? _validateText(String? value, int minimum, int maximum) {
    final count = value?.trim().runes.length ?? 0;
    if (count < minimum) return minimum == 3 ? tr('Enter at least 3 characters') : tr('Enter at least 10 characters');
    if (count > maximum) return tr('Use no more than {0} characters.', [maximum]);
    return null;
  }

  Future<void> _send() async {
    if (_sending || _picking || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _locked = true;
      _error = null;
    });
    try {
      final id = await _service.send(
        requestId: _requestId,
        bookingId: widget.bookingId,
        subject: _subject.text,
        description: _description.text,
        photos: List.unmodifiable(_photos),
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return PopScope(
      canPop: !_sending && !_picking,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          title: Text(tr(widget.bookingId == null ? 'Contact Admin' : 'Request Admin Support')),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.bookingId != null)
                ProviderSupportCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Linked booking'), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _primaryOrange)),
                      const SizedBox(height: 6),
                      Text(widget.bookingId!),
                    ],
                  ),
                ),
              if (widget.bookingId != null) const SizedBox(height: 20),
              TextFormField(
                controller: _subject,
                readOnly: _locked,
                maxLength: 150,
                decoration: InputDecoration(labelText: tr('Subject')),
                validator: (v) => _validateText(v, 3, 150),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                readOnly: _locked,
                minLines: 5,
                maxLines: 10,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: tr(widget.bookingId == null ? 'Your message' : 'Describe the issue'),
                  alignLabelWithHint: true,
                ),
                validator: (v) => _validateText(v, 10, 4000),
              ),
              const SizedBox(height: 16),
              Text(tr('Photos (optional)'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(tr('Up to 3 photos · 5 MB each')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.memory(_photos[i].bytes, fit: BoxFit.cover, cacheWidth: 240),
                            ),
                          ),
                          if (!_locked)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton.filled(
                                onPressed: () => setState(() => _photos.removeAt(i)),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              if (!_locked && _photos.length < 3)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _picking ? null : () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(tr('Gallery')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _picking ? null : () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(tr('Camera')),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_picking) const LinearProgressIndicator(),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    tr(_error!),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _primaryOrange, foregroundColor: Colors.white),
                onPressed: _sending || _picking ? null : _send,
                child: Text(tr(_sending ? 'Sending request…' : _locked ? 'Retry sending' : 'Send to Admin')),
              ),
              SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }
}

class ProviderSupportDetailScreen extends StatefulWidget {
  final String id;
  final ProviderSupportService service;
  const ProviderSupportDetailScreen({super.key, required this.id, required this.service});
  @override
  State<ProviderSupportDetailScreen> createState() => _ProviderDetailState();
}

class _ProviderDetailState extends State<ProviderSupportDetailScreen> {
  static const _primaryOrange = Color(0xFFFF6B00);
  Map<String, dynamic>? _row;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.service.requests(id: widget.id);
      if (mounted) {
        setState(() {
          _row = rows.isEmpty ? null : rows.first;
          _error = rows.isEmpty ? 'Support request not found.' : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final row = _row;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: Text(tr('Admin Support Request')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null)
              ProviderSupportCard(
                child: Column(
                  children: [
                    Text(tr(_error!)),
                    TextButton(onPressed: _load, child: Text(tr('Retry'))),
                  ],
                ),
              ),
            if (row == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (row != null) ...[
              ProviderSupportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(
                      label: Text(tr(row['status'] as String), style: const TextStyle(color: _primaryOrange, fontWeight: FontWeight.w600)),
                      side: const BorderSide(color: _primaryOrange),
                      backgroundColor: _primaryOrange.withValues(alpha: .08),
                    ),
                    const SizedBox(height: 12),
                    Text(row['subject'] as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _primaryOrange, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(formatSupportDate(row['created_at']), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    SelectableText(row['description'] as String),
                    // 移除 booking_id 的展示（因为新表没这个字段）
                    if (row['booking_id'] != null) ...[
                      const SizedBox(height: 16),
                      Text('${tr('Booking reference')}: ${row['booking_id']}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final path in (row['attachment_paths'] as List? ?? []))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SupportPhoto(path: path as String, service: widget.service),
                ),
              ProviderSupportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _primaryOrange.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.mark_chat_read_outlined, color: _primaryOrange, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(tr('Admin response'), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _primaryOrange, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    Divider(height: 28, color: _primaryOrange.withValues(alpha: .2)),
                    // 修改 2：把 resolution 改成 admin_reply
                    if ((row['admin_reply'] as String?)?.trim().isNotEmpty == true)
                      SelectableText(row['admin_reply'] as String, style: const TextStyle(height: 1.5))
                    else
                      Text(tr('Your request is waiting for admin review. Pull down to check for updates.'), style: const TextStyle(height: 1.5, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}