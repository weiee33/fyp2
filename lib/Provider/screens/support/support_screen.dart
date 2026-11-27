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

  // 👇 删除了没用到的 _showAppDialog

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

  String _translate(BuildContext context, String en, String zh, String ms) {
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'zh') return zh;
    if (lang == 'ms') return ms;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _translate(context, 'Help Centre', '帮助中心', 'Pusat Bantuan'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(20),
          children: [
            ProviderSupportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.support_agent_rounded, color: _primaryOrange, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    _translate(context, 'How can we help?', '我们能帮您什么？', 'Bagaimana kami boleh membantu?'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _translate(context, 'Ask a question, share feedback or make a complaint.', '提出问题、分享反馈或提出投诉。', 'Tanya soalan, kongsi maklum balas atau buat aduan.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _primaryOrange, foregroundColor: Colors.white),
                    onPressed: _compose,
                    child: Text(_translate(context, 'Contact Support', '联系客服', 'Hubungi Sokongan')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(_translate(context, 'Before you send', '发送前', 'Sebelum anda hantar'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ProviderSupportCard(
              child: Column(
                children: [
                  _HelpTopic(
                    title: _translate(context, 'Booking and payout help', '预约与付款帮助', 'Bantuan tempahan dan pembayaran'),
                    body: _translate(context, 'Open Booking Details to contact your customer or request support linked to that booking.', '打开预约详情联系您的客户或请求与该预约相关的支持。', 'Buka Butiran Tempahan untuk menghubungi pelanggan anda atau meminta sokongan berkaitan tempahan tersebut.'),
                  ),
                  const Divider(),
                  _HelpTopic(
                    title: _translate(context, 'Account and privacy help', '账户与隐私帮助', 'Bantuan akaun dan privasi'),
                    body: _translate(context, 'Use Profile to update your business details, services, service areas and working hours.', '使用“我的”来更新您的业务详情、服务、服务区域和工作时间。', 'Gunakan Profil untuk mengemas kini butiran perniagaan, perkhidmatan, kawasan perkhidmatan dan waktu bekerja anda.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(_translate(context, 'Your support requests', '您的支持请求', 'Permintaan sokongan anda'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_error != null)
              ProviderSupportCard(
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: Text(_translate(context, 'Retry', '重试', 'Cuba lagi'))),
                  ],
                ),
              ),
            if (_requests.isEmpty && !_loading && _error == null)
              ProviderSupportCard(
                child: Text(_translate(context, 'No support requests yet. Your messages and support responses will appear here.', '暂无支持请求。您的消息和支持回复将在此显示。', 'Tiada permintaan sokongan lagi. Mesej dan respons sokongan anda akan dipaparkan di sini.')),
              ),
            for (final row in _requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ProviderSupportCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['subject'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${_translate(context, row['booking_id'] == null ? 'General enquiry' : 'Booking support', row['booking_id'] == null ? '一般咨询' : '预约支持', row['booking_id'] == null ? 'Pertanyaan umum' : 'Sokongan tempahan')}\n${row['status'] as String} · ${formatSupportDate(row['created_at'])}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(row['id'] as String),
                  ),
                ),
              ),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: _primaryOrange))),
            if (_more && !_loading)
              TextButton(onPressed: () => _load(more: true), child: Text(_translate(context, 'Load more', '加载更多', 'Muat lagi'))),
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

  // 👇 删除了没用到的 _showAppDialog

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
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String? _validateText(String? value, int minimum, int maximum) {
    final count = value?.trim().runes.length ?? 0;
    if (count < minimum) {
      final lang = Localizations.localeOf(context).languageCode;
      if (lang == 'zh') return minimum == 3 ? '请输入至少 3 个字符' : '请输入至少 10 个字符';
      if (lang == 'ms') return minimum == 3 ? 'Masukkan sekurang-kurangnya 3 aksara' : 'Masukkan sekurang-kurangnya 10 aksara';
      return minimum == 3 ? 'Enter at least 3 characters' : 'Enter at least 10 characters';
    }
    if (count > maximum) {
      final lang = Localizations.localeOf(context).languageCode;
      if (lang == 'zh') return '最多使用 $maximum 个字符。';
      if (lang == 'ms') return 'Gunakan tidak lebih daripada $maximum aksara.';
      return 'Use no more than $maximum characters.';
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
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _translate(BuildContext context, String en, String zh, String ms) {
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'zh') return zh;
    if (lang == 'ms') return ms;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return PopScope(
      canPop: !_sending && !_picking,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: _primaryOrange,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _translate(context, widget.bookingId == null ? 'Contact Support' : 'Request Support', widget.bookingId == null ? '联系客服' : '请求支持', widget.bookingId == null ? 'Hubungi Sokongan' : 'Minta Sokongan'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.bookingId != null)
                ProviderSupportCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_translate(context, 'Linked booking', '关联预约', 'Tempahan berkaitan'), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _primaryOrange)),
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
                decoration: InputDecoration(labelText: _translate(context, 'Subject', '主题', 'Subjek')),
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
                  labelText: _translate(context, widget.bookingId == null ? 'Your message' : 'Describe the issue', widget.bookingId == null ? '您的消息' : '描述问题', widget.bookingId == null ? 'Mesej anda' : 'Terangkan isu'),
                  alignLabelWithHint: true,
                ),
                validator: (v) => _validateText(v, 10, 4000),
              ),
              const SizedBox(height: 16),
              Text(_translate(context, 'Photos (optional)', '照片（可选）', 'Foto (pilihan)'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_translate(context, 'Up to 3 photos · 5 MB each', '最多 3 张照片 · 每张 5 MB', 'Sehingga 3 foto · 5 MB setiap satu')),
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
                          label: Text(_translate(context, 'Gallery', '相册', 'Galeri')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _picking ? null : () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(_translate(context, 'Camera', '相机', 'Kamera')),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_picking) const LinearProgressIndicator(),
              const SizedBox(height: 20),
              // 👇 显示错误信息
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _primaryOrange, foregroundColor: Colors.white),
                onPressed: _sending || _picking ? null : _send,
                child: Text(
                  _translate(context, _sending ? 'Sending request…' : _locked ? 'Retry sending' : 'Send to Admin', _sending ? '发送请求中...' : _locked ? '重试发送' : '发送给管理员', _sending ? 'Menghantar permintaan...' : _locked ? 'Cuba hantar semula' : 'Hantar kepada Admin'),
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

  // 👇 删除了没用到的 _showAppDialog

  String _translate(BuildContext context, String en, String zh, String ms) {
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'zh') return zh;
    if (lang == 'ms') return ms;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final row = _row;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _translate(context, 'Admin Support Request', '管理员支持请求', 'Permintaan Sokongan Admin'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null)
              ProviderSupportCard(
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: Text(_translate(context, 'Retry', '重试', 'Cuba lagi'))),
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
                      label: Text(row['status'] as String, style: const TextStyle(color: _primaryOrange, fontWeight: FontWeight.w600)),
                      side: const BorderSide(color: _primaryOrange),
                      backgroundColor: _primaryOrange.withValues(alpha: .08),
                    ),
                    const SizedBox(height: 12),
                    Text(row['subject'] as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _primaryOrange, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(formatSupportDate(row['created_at']), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    SelectableText(row['description'] as String),
                    if (row['booking_id'] != null) ...[
                      const SizedBox(height: 16),
                      Text('${_translate(context, 'Booking reference', '预约参考', 'Rujukan tempahan')}: ${row['booking_id']}', style: Theme.of(context).textTheme.bodySmall),
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
                          child: Text(_translate(context, 'Admin response', '管理员回复', 'Respons admin'), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _primaryOrange, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    Divider(height: 28, color: _primaryOrange.withValues(alpha: .2)),
                    if ((row['admin_reply'] as String?)?.trim().isNotEmpty == true)
                      SelectableText(row['admin_reply'] as String, style: const TextStyle(height: 1.5))
                    else
                      Text(_translate(context, 'Your request is waiting for admin review. Pull down to check for updates.', '您的请求正在等待管理员审核。下拉刷新以查看更新。', 'Permintaan anda sedang menunggu semakan admin. Tarik ke bawah untuk menyemak kemas kini.'), style: const TextStyle(height: 1.5, color: Colors.grey)),
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