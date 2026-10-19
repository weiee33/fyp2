import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../shared/localization/app_language.dart';
import '../../core/customer_theme.dart';
import '../../models/booking_model.dart';
import '../../services/customer_support_service.dart';
import '../../services/customer_transaction_service.dart';
import '../../widgets/customer_dialogs.dart';
import '../../widgets/customer_refresh.dart';
import '../../widgets/customer_scaffold.dart';

class CustomerSupportScreen extends StatefulWidget {
  final CustomerSupportService? service;
  const CustomerSupportScreen({super.key, this.service});
  @override
  State<CustomerSupportScreen> createState() => _SupportState();
}

class _SupportState extends State<CustomerSupportScreen> {
  late final _service = widget.service ?? CustomerSupportService();
  final _requests = <Map<String, dynamic>>[];
  bool _loading = false, _more = false;
  String? _error;
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
      if (mounted) setState(() => _error = CustomerDialogs.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compose() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSupportComposeScreen(service: _service),
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
        builder: (_) => CustomerSupportDetailScreen(id: id, service: _service),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return CustomerScaffold(
      appBar: AppBar(title: Text(tr('Help Centre'))),
      body: CustomerRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SupportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.support_agent_rounded,
                    color: CustomerTheme.primary,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('How can we help?'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('Ask a question, share feedback or make a complaint.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: CustomerTheme.actionStyle(),
                    onPressed: _compose,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr('Contact Support')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tr('Before you send'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SupportCard(
              child: Column(
                children: [
                  _HelpTopic(
                    title: tr('Booking and payment help'),
                    body: tr(
                      'Open Booking Details to contact your provider or request support linked to that booking. Wait for provider acceptance before paying. A chat message alone does not reserve a time slot.',
                    ),
                  ),
                  const Divider(),
                  _HelpTopic(
                    title: tr('Account and privacy help'),
                    body: tr(
                      'Use Profile & Preferences to update your details and Account & Security to manage your sign-in or request account deletion. Contact support here if you need help accessing or correcting your information.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr('Your support requests'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SupportCard(
                child: Column(
                  children: [
                    Text(tr(_error!)),
                    TextButton(onPressed: _load, child: Text(tr('Retry'))),
                  ],
                ),
              ),
            if (_requests.isEmpty && !_loading && _error == null)
              SupportCard(
                child: Text(
                  tr(
                    'No support requests yet. Your messages and support responses will appear here.',
                  ),
                ),
              ),
            for (final row in _requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SupportCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      row['booking_id'] == null
                          ? Icons.support_agent_rounded
                          : Icons.event_note_outlined,
                      color: CustomerTheme.primary,
                    ),
                    title: Text(
                      row['subject'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${tr(row['booking_id'] == null ? 'General enquiry' : 'Booking support')}\n${tr(row['status'] as String)} · ${_date(row['created_at'])}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(row['dispute_id'] as String),
                  ),
                ),
              ),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_more && !_loading)
              TextButton(
                onPressed: () => _load(more: true),
                child: Text(tr('Load more')),
              ),
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

class CustomerSupportComposeScreen extends StatefulWidget {
  final String? bookingId;
  final CustomerBooking? booking;
  final CustomerSupportService? service;
  final Future<XFile?> Function(ImageSource)? pickPhoto;
  CustomerSupportComposeScreen({
    super.key,
    this.bookingId,
    this.booking,
    this.service,
    this.pickPhoto,
  }) : assert(booking == null || bookingId == booking.id);
  @override
  State<CustomerSupportComposeScreen> createState() => _ComposeState();
}

class _ComposeState extends State<CustomerSupportComposeScreen> {
  late final _service = widget.service ?? CustomerSupportService();
  final _requestId = CustomerTransactionService.newRequestId();
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController(),
      _description = TextEditingController();
  final _photos = <SupportPhoto>[];
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
      final file =
          await (widget.pickPhoto?.call(source) ??
              ImagePicker().pickImage(
                source: source,
                maxWidth: 2000,
                maxHeight: 2000,
                imageQuality: 85,
              ));
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const FormatException('Choose a photo smaller than 5 MB.');
      }
      final photo = SupportPhoto(await file.readAsBytes());
      try {
        final codec = await ui.instantiateImageCodec(
          photo.bytes,
          targetWidth: 100,
        );
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } catch (_) {
        throw const FormatException(
          'This photo could not be read. Choose another photo.',
        );
      }
      if (mounted) {
        setState(() {
          _photos.add(photo);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = CustomerDialogs.errorMessage(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String? _validateText(String? value, int minimum, int maximum) {
    // PostgreSQL length(text) counts Unicode code points, not UTF-16 units.
    final count = value?.trim().runes.length ?? 0;
    if (count < minimum) {
      return minimum == 3
          ? tr('Enter at least 3 characters')
          : tr('Enter at least 10 characters');
    }
    if (count > maximum) {
      return tr('Use no more than {0} characters.', [maximum]);
    }
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
      if (mounted) setState(() => _error = CustomerDialogs.errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return PopScope(
      canPop: !_sending && !_picking,
      child: CustomerScaffold(
        appBar: AppBar(
          title: Text(
            tr(
              widget.bookingId == null
                  ? 'Contact Support'
                  : 'Request Booking Support',
            ),
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.bookingId != null)
                SupportCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.event_note_outlined,
                        color: CustomerTheme.primary,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Linked booking'),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: CustomerTheme.primaryDark),
                            ),
                            const SizedBox(height: 6),
                            if (widget.booking case final booking?) ...[
                              Text(
                                booking.serviceName,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(booking.providerName),
                              const SizedBox(height: 6),
                              Text(
                                '${booking.appointmentLabel} · ${tr('Malaysia time')}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                booking.shortId,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ] else
                              Text(widget.bookingId!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.bookingId != null) const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('support-subject'),
                controller: _subject,
                readOnly: _locked,
                maxLength: 150,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Subject')),
                validator: (v) => _validateText(v, 3, 150),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('support-description'),
                controller: _description,
                readOnly: _locked,
                minLines: 5,
                maxLines: 10,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr(
                    widget.bookingId == null
                        ? 'Your message'
                        : 'Describe the booking issue',
                  ),
                  alignLabelWithHint: true,
                ),
                validator: (v) => _validateText(v, 10, 4000),
              ),
              const SizedBox(height: 16),
              Text(
                tr('Photos (optional)'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
                              child: Image.memory(
                                _photos[i].bytes,
                                fit: BoxFit.cover,
                                cacheWidth: 240,
                              ),
                            ),
                          ),
                          if (!_locked)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton.filled(
                                tooltip: tr('Remove photo'),
                                onPressed: () =>
                                    setState(() => _photos.removeAt(i)),
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
                          style: CustomerTheme.actionStyle(outlined: true),
                          onPressed: _picking
                              ? null
                              : () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            tr('Gallery'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: CustomerTheme.actionStyle(outlined: true),
                          onPressed: _picking
                              ? null
                              : () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(
                            tr('Camera'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_picking) const LinearProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                tr('Replies appear in Help Centre.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                alignment: Alignment.topCenter,
                child: _error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _locked
                                ? '${tr(_error!)}\n${tr('Your request has not been confirmed. Retry with the same details, or check Help Centre before starting another request.')}'
                                : tr(_error!),
                            style: const TextStyle(color: CustomerTheme.danger),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: CustomerTheme.actionStyle(),
                onPressed: _sending || _picking ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  tr(
                    _sending
                        ? 'Sending request…'
                        : _locked
                        ? 'Retry sending'
                        : 'Send request',
                  ),
                ),
              ),
              SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerSupportDetailScreen extends StatefulWidget {
  final String id;
  final CustomerSupportService service;
  const CustomerSupportDetailScreen({
    super.key,
    required this.id,
    required this.service,
  });
  @override
  State<CustomerSupportDetailScreen> createState() => _DetailState();
}

class _DetailState extends State<CustomerSupportDetailScreen> {
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
      if (mounted) setState(() => _error = CustomerDialogs.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final row = _row;
    return CustomerScaffold(
      appBar: AppBar(title: Text(tr('Support Request'))),
      body: CustomerRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null)
              SupportCard(
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
              SupportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(
                      label: Text(
                        tr(row['status'] as String),
                        style: const TextStyle(
                          color: CustomerTheme.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      side: const BorderSide(color: CustomerTheme.primary),
                      avatar: const Icon(
                        Icons.support_agent,
                        size: 18,
                        color: CustomerTheme.primary,
                      ),
                      backgroundColor: CustomerTheme.primary.withValues(
                        alpha: .08,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      row['subject'] as String,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: CustomerTheme.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _date(row['created_at']),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(row['description'] as String),
                    if (row['booking_id'] != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        '${tr('Booking reference')}: ${row['booking_id']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final path in (row['attachment_paths'] as List? ?? []))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SupportPhoto(
                    path: path as String,
                    service: widget.service,
                  ),
                ),
              SupportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: CustomerTheme.primary.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.mark_chat_read_outlined,
                            color: CustomerTheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('Support response'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: CustomerTheme.primaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    Divider(
                      height: 28,
                      color: CustomerTheme.primary.withValues(alpha: .2),
                    ),
                    if ((row['resolution'] as String?)?.trim().isNotEmpty ==
                        true)
                      SelectableText(
                        row['resolution'] as String,
                        style: const TextStyle(height: 1.5),
                      )
                    else
                      Text(
                        tr(
                          'Your request is waiting for review. Pull down to check for updates.',
                        ),
                        style: const TextStyle(
                          height: 1.5,
                          color: CustomerTheme.textSecondary,
                        ),
                      ),
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

class _SupportPhoto extends StatefulWidget {
  final String path;
  final CustomerSupportService service;
  const _SupportPhoto({required this.path, required this.service});
  @override
  State<_SupportPhoto> createState() => _SupportPhotoState();
}

class _SupportPhotoState extends State<_SupportPhoto> {
  late Future<String> _url = widget.service.photoUrl(widget.path);
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      final retry = TextButton.icon(
        onPressed: () =>
            setState(() => _url = widget.service.photoUrl(widget.path)),
        icon: const Icon(Icons.refresh),
        label: Text(tr('Retry photo')),
      );
      if (snapshot.hasError) return retry;
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          snapshot.data!,
          fit: BoxFit.contain,
          errorBuilder: (_, e, s) => retry,
        ),
      );
    },
  );
}

class SupportCard extends StatelessWidget {
  final Widget child;
  const SupportCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: CustomerTheme.borderColor),
    ),
    child: child,
  );
}

String _date(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '' : DateFormat.yMMMd().format(date.toLocal());
}
