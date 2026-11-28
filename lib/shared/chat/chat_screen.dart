import 'chat_attachments.dart';
import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'chat_photo.dart';
import '../../Customer/widgets/customer_refresh.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../Customer/core/customer_theme.dart';
import '../../Customer/widgets/customer_dialogs.dart';
import '../../Customer/services/customer_transaction_service.dart';
import 'chat_service.dart';

class ConversationScreen extends StatefulWidget {
  final String? conversationId, providerId, bookingId;
  final ChatService? service;
  final bool customer;
  final Future<XFile?> Function(ImageSource)? pickPhoto;
  final Future<List<XFile>> Function(ImageSource)? pickPhotos;
  const ConversationScreen({
    super.key,
    this.conversationId,
    this.providerId,
    this.bookingId,
    this.service,
    this.pickPhoto,
    this.pickPhotos,
    this.customer = true,
  });
  @override
  State<ConversationScreen> createState() => _ConversationState();
}

class _ConversationState extends State<ConversationScreen> {
  late final _service = widget.service ?? ChatService();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  String? _id, _error, _retryBody, _retryId;
  String _name = 'Chat';
  String? _photoError;
  bool _pickingPhoto = false;
  int _clearedThrough = 0;
  bool _loading = true,
      _sending = false,
      _canSend = false,
      _more = false,
      _olderLoading = false,
      _refreshing = false;
  ChatUpdates? _updates;
  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _updates?.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _id =
          widget.conversationId ??
          await _service.open(
            providerId: widget.providerId,
            bookingId: widget.bookingId,
          );
      if (!mounted) return;
      await _refresh();
      if (mounted) {
        _updates ??= ChatUpdates(_service, _refresh, conversationId: _id);
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            _service.isLive) {
          final lost = await ImagePicker().retrieveLostData();
          if (lost.files?.isNotEmpty == true) {
            if (!mounted) return;
            final photos = await _preparePhotos(lost.files!, context, 0);
            if (mounted && photos.isNotEmpty) await _reviewPhotos(photos);
          }
          if (lost.exception != null && mounted) {
            setState(
              () => _photoError =
                  'The previous photo could not be recovered. Choose it again.',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = CustomerDialogs.errorMessage(e);
          _loading = false;
        });
        await CustomerDialogs.error(context, e);
      }
    }
  }

  Future<void> _refresh() async {
    if (_id == null || _refreshing || !mounted) return;
    _refreshing = true;
    try {
      final data = await _service.history(_id!);
      final newest = ChatService.rows(data['messages']);
      final serverCleared = (data['cleared_through'] as num?)?.toInt() ?? 0;
      if (serverCleared > _clearedThrough) _clearedThrough = serverCleared;
      final previousNewest = _messages.isEmpty
          ? null
          : (_messages.first['message_id'] as num).toInt();
      var page = newest;
      // Fill a burst larger than one page before merging with previously loaded history.
      while (previousNewest != null &&
          page.length == 40 &&
          (page.last['message_id'] as num).toInt() > previousNewest) {
        final earlier = await _service.history(
          _id!,
          before: (page.last['message_id'] as num).toInt(),
        );
        final earlierBoundary =
            (earlier['cleared_through'] as num?)?.toInt() ?? 0;
        if (earlierBoundary > _clearedThrough) {
          _clearedThrough = earlierBoundary;
        }
        page = ChatService.rows(earlier['messages']);
        newest.addAll(page);
        if (page.isEmpty) break;
      }
      if (!mounted) return;
      // Keep older loaded pages; merge by server identity to avoid duplicate retries.
      final merged = <int, Map<String, dynamic>>{
        for (final m in _messages.where(
          (m) => (m['message_id'] as num).toInt() > _clearedThrough,
        ))
          (m['message_id'] as num).toInt(): m,
        for (final m in newest.where(
          (m) => (m['message_id'] as num).toInt() > _clearedThrough,
        ))
          (m['message_id'] as num).toInt(): m,
      };
      // A cleared conversation must not resurrect previously loaded local rows.
      if (newest.isEmpty) merged.clear();
      setState(() {
        _messages
          ..clear()
          ..addAll(
            merged.values.toList()..sort(
              (a, b) =>
                  (b['message_id'] as num).compareTo(a['message_id'] as num),
            ),
          );
        _name = data['peer_name'] as String? ?? 'Chat';
        _canSend = data['can_send'] == true;
        if (_loading || previousNewest == null) _more = newest.length >= 40;
        _error = null;
        _loading = false;
      });
      if (newest.isNotEmpty &&
          ModalRoute.of(context)?.isCurrent == true &&
          (!_scroll.hasClients || _scroll.offset < 80) &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
        await _service.manage(
          _id!,
          'read',
          readThrough: (newest.first['message_id'] as num).toInt(),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = CustomerDialogs.errorMessage(e);
        final notify = _error != message;
        setState(() {
          _error = message;
          _loading = false;
        });
        if (notify) CustomerDialogs.error(context, e);
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _older() async {
    if (_olderLoading || _messages.isEmpty) return;
    setState(() => _olderLoading = true);
    try {
      final data = await _service.history(
        _id!,
        before: (_messages.last['message_id'] as num).toInt(),
      );
      final serverCleared = (data['cleared_through'] as num?)?.toInt() ?? 0;
      if (serverCleared > _clearedThrough) _clearedThrough = serverCleared;
      final rows = ChatService.rows(data['messages'])
          .where((m) => (m['message_id'] as num).toInt() > _clearedThrough)
          .toList();
      if (mounted) {
        setState(() {
          _messages.removeWhere(
            (m) => (m['message_id'] as num).toInt() <= _clearedThrough,
          );
          final ids = _messages.map((m) => m['message_id']).toSet();
          _messages.addAll(rows.where((m) => !ids.contains(m['message_id'])));
          _more = rows.length == 40;
        });
      }
    } catch (e) {
      if (mounted) await CustomerDialogs.error(context, e);
    } finally {
      if (mounted) setState(() => _olderLoading = false);
    }
  }

  Future<bool> _send({
    List<ChatAttachment> photos = const [],
    String? caption,
  }) async {
    final body = (caption ?? _text.text).trim();
    if (_sending || _pickingPhoto || !_canSend || _id == null) return false;
    if ((body.isEmpty && photos.isEmpty) || body.length > 2000) {
      await CustomerDialogs.show(
        context,
        message: tr('Enter a message of 1–2000 characters.'),
      );
      return false;
    }
    if (_retryBody != body) {
      _retryBody = body;
      _retryId = CustomerTransactionService.newRequestId();
    }
    setState(() => _sending = true);
    try {
      final messages = photos.isEmpty
          ? [await _service.send(_id!, body, _retryId!)]
          : await _service.sendPhotos(_id!, photos, body);
      if (!mounted) return false;
      setState(() {
        for (final message in messages) {
          _recordSent(message);
        }
        _text.clear();
      });
      _retryBody = null;
      _retryId = null;
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      await _refresh();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        await CustomerDialogs.error(context, e);
      }
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _recordSent(Map<String, dynamic> message) {
    if (!_messages.any((m) => m['message_id'] == message['message_id'])) {
      _messages.insert(0, message);
    }
  }

  Future<void> _attachPhotos() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final photos = await _pickPhotos(context, 0);
    if (mounted && photos.isNotEmpty) await _reviewPhotos(photos);
  }

  Future<List<ChatAttachment>> _pickPhotos(
    BuildContext owner,
    int count,
  ) async {
    if (_sending || _pickingPhoto || !_canSend) return [];
    setState(() {
      _pickingPhoto = true;
      _photoError = null;
    });
    try {
      if (!await photosFit(owner, count + 1) || !owner.mounted) return [];
      final source = await showModalBottomSheet<ImageSource>(
        context: owner,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(tr('Choose from gallery')),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(tr('Take a photo')),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !owner.mounted || source == null) return [];
      final files = widget.pickPhoto == null
          ? await (widget.pickPhotos ?? pickChatPhotos)(source)
          : [if (await widget.pickPhoto!(source) case final file?) file];
      if (files.isEmpty || !owner.mounted) return [];
      return await _preparePhotos(files, owner, count);
    } catch (_) {
      if (owner.mounted) {
        await CustomerDialogs.show(
          owner,
          message: tr(
            'Could not open your photo. Check camera/photo permissions and try again.',
          ),
        );
      }
      return [];
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<List<ChatAttachment>> _preparePhotos(
    List<XFile> files,
    BuildContext owner,
    int count,
  ) async {
    if (!await photosFit(owner, count + files.length)) return [];
    final added = <ChatAttachment>[];
    try {
      for (final file in files) {
        if (await file.length() > 5 * 1024 * 1024) {
          throw const FormatException('Choose a photo smaller than 5 MB.');
        }
        final bytes = await file.readAsBytes();
        ChatService.photoMime(bytes);
        added.add(
          ChatAttachment(bytes, CustomerTransactionService.newRequestId()),
        );
      }
    } on FormatException catch (error) {
      if (owner.mounted) await CustomerDialogs.error(owner, error);
      return [];
    }
    return added;
  }

  Future<void> _reviewPhotos(List<ChatAttachment> photos) async {
    var caption = _text.text;
    while (_canSend && photos.isNotEmpty) {
      if (!mounted) return;
      final send = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => StatefulBuilder(
          builder: (sheet, refresh) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              12 + MediaQuery.viewInsetsOf(sheet).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatPhotoStrip(
                    photos: photos,
                    onRemove: (photo) {
                      photos.remove(photo);
                      if (photos.isEmpty) {
                        Navigator.pop(sheet);
                      } else {
                        refresh(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        tooltip: tr('Attach photo'),
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () async {
                          final added = await _pickPhotos(sheet, photos.length);
                          if (sheet.mounted && added.isNotEmpty) {
                            refresh(() => photos.addAll(added));
                          }
                        },
                      ),
                      Expanded(
                        child: TextFormField(
                          initialValue: caption,
                          onChanged: (value) => caption = value,
                          maxLength: 2000,
                          decoration: InputDecoration(
                            hintText: tr('Add a caption'),
                            counterText: '',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Send message'),
                        icon: const Icon(
                          Icons.send,
                          color: CustomerTheme.primary,
                        ),
                        onPressed: () => Navigator.pop(sheet, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!mounted || send != true) return;
      if (await _send(photos: photos, caption: caption)) return;
    }
  }

  void _openGallery(String path) {
    var before = _messages.isEmpty
        ? null
        : (_messages.last['message_id'] as num).toInt();
    var more = _more;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPhotoGallery(
          paths: _messages.reversed
              .where((m) => m['attachment_path'] is String)
              .map((m) => m['attachment_path'] as String)
              .toList(),
          initialPath: path,
          service: _service,
          loadEarlier: () async {
            final paths = <String>[];
            while (more && paths.isEmpty) {
              final data = await _service.history(_id!, before: before);
              final rows = ChatService.rows(data['messages']);
              more = rows.length == 40;
              if (rows.isNotEmpty) {
                before = (rows.last['message_id'] as num).toInt();
              }
              paths.addAll(
                rows.reversed
                    .where((m) => m['attachment_path'] is String)
                    .map((m) => m['attachment_path'] as String),
              );
            }
            return paths;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Theme(
      data: CustomerTheme.lightTheme,
      child: CustomerScaffold(
        enabled: widget.customer,
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: Text(_name, overflow: TextOverflow.ellipsis),
          actions: [
            if (!widget.customer)
              // A reversed chat starts at its visual bottom. Use an explicit
              // refresh action so browsing older/newer messages never reloads it.
              IconButton(
                tooltip: MaterialLocalizations.of(
                  context,
                ).refreshIndicatorSemanticLabel,
                onPressed: _loading ? null : (_id == null ? _start : _refresh),
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_error != null)
                MaterialBanner(
                  content: Text(tr(_error!)),
                  actions: [
                    TextButton(
                      onPressed: _id == null ? _start : _refresh,
                      child: Text(tr('Retry')),
                    ),
                  ],
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : CustomerRefresh(
                        customer: widget.customer,
                        onRefresh: _id == null ? _start : _refresh,
                        child: ListView.builder(
                          physics: widget.customer
                              ? customerScrollPhysics(context)
                              : const ClampingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.isEmpty
                              ? 1
                              : _messages.length + (_more ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_messages.isEmpty) {
                              return Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text(tr('Start the conversation.')),
                                ),
                              );
                            }
                            if (index == _messages.length) {
                              return TextButton(
                                onPressed: _olderLoading ? null : _older,
                                child: Text(
                                  tr(
                                    _olderLoading
                                        ? 'Loading…'
                                        : 'Load earlier messages',
                                  ),
                                ),
                              );
                            }
                            final m = _messages[index],
                                mine = m['is_mine'] == true;
                            final date = DateTime.tryParse(
                              m['created_at'].toString(),
                            )?.toLocal();
                            return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * .78,
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? CustomerTheme.primarySurface
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (m['attachment_path'] is String)
                                      ChatPhoto(
                                        key: ValueKey(m['attachment_path']),
                                        path: m['attachment_path'] as String,
                                        service: _service,
                                        onOpen: () => _openGallery(
                                          m['attachment_path'] as String,
                                        ),
                                      )
                                    else
                                      SelectionArea(
                                        child: Text(m['body'].toString()),
                                      ),
                                    if (m['photo_caption']
                                        case final String caption)
                                      SelectionArea(child: Text(caption)),
                                    const SizedBox(height: 4),
                                    if (date != null)
                                      Text(
                                        tr(
                                          DateFormat(
                                            'd MMM, HH:mm',
                                          ).format(date),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              if (!_loading && !_canSend)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    tr(
                      'Messaging is unavailable. Refresh this conversation or contact support.',
                    ),
                  ),
                ),
              if (_photoError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    tr(_photoError!),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: trOrNull('Attach photo'),
                      onPressed: _canSend && !_sending && !_pickingPhoto
                          ? _attachPhotos
                          : null,
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: CustomerTheme.primary,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        enabled: _canSend && !_sending,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: trOrNull('Type a message'),
                          counterText: '',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: trOrNull('Send message'),
                      onPressed: _canSend && !_sending && !_pickingPhoto
                          ? _send
                          : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.send,
                              color: CustomerTheme.primary,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
