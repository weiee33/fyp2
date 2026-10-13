import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_ai_service.dart';
import '../../services/customer_ai_speech.dart';
import '../../services/customer_transaction_service.dart';
import '../booking/customer_booking_detail_screen.dart';
import '../booking/customer_bookings_screen.dart';
import '../browsing/customer_provider_detail_screen.dart';
import '../browsing/customer_service_list_screen.dart';
import '../notifications/customer_notification_screen.dart';
import '../profile/customer_profile_screen.dart';
import '../profile/customer_saved_addresses_screen.dart';
import '../review/customer_my_reviews_screen.dart';
import '../payment/customer_checkout_screen.dart';

class CustomerAiScreen extends StatefulWidget {
  final CustomerAiService? service;
  final CustomerAiSpeech? speech;
  final Future<Uint8List?> Function(ImageSource)? pickPhoto;
  final Future<void> Function(Map<String, dynamic>)? onNavigate;
  const CustomerAiScreen({
    super.key,
    this.service,
    this.speech,
    this.pickPhoto,
    this.onNavigate,
  });
  @override
  State<CustomerAiScreen> createState() => _CustomerAiScreenState();
}

class _CustomerAiScreenState extends State<CustomerAiScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? CustomerAiService();
  late final _speech = widget.speech ?? CustomerAiSpeech();
  final _text = TextEditingController(), _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String? _conversation, _error, _imagePath, _requestId, _retryText;
  String _createId = CustomerTransactionService.newRequestId(),
      _mode = 'chat',
      _retryMode = 'chat',
      _voicePrefix = '';
  Uint8List? _photo;
  bool _busy = false,
      _older = true,
      _listening = false,
      _hold = false,
      _voiceStarting = false;
  final Set<String> _doneActions = {};
  final Map<String, Future<Uint8List>> _photoCache = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.cancel());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _hold = false;
      unawaited(_speech.cancel());
      if (mounted) setState(() => _listening = false);
    }
  }

  String _message(Object e) => e is FormatException
      ? e.message
      : e.toString().contains('PostgrestException')
      ? 'This action could not be completed. Refresh or ask for a new action card.'
      : 'Connection unavailable. Please retry.';
  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    if (_busy || (_text.text.trim().isEmpty && _photo == null)) return;
    await _speech.cancel();
    _hold = false;
    final message = _text.text.trim();
    if (message.length > 4000) {
      setState(() => _error = 'Keep your message under 4000 characters.');
      return;
    }
    if (_requestId == null || _retryText != message || _retryMode != _mode) {
      _requestId = CustomerTransactionService.newRequestId();
      _retryText = message;
      _retryMode = _mode;
    }
    setState(() {
      _busy = true;
      _error = null;
      _listening = false;
    });
    try {
      _conversation ??= (await _service.create(_createId))['id'].toString();
      if (_photo != null && _imagePath == null) {
        _imagePath = await _service.upload(
          _conversation!,
          _requestId!,
          _photo!,
        );
      }
      final reply = await _service.send(
        conversation: _conversation!,
        requestId: _requestId!,
        message: message,
        mode: _mode,
        imagePath: _imagePath,
      );
      final history = await _service.history(_conversation!);
      if (!mounted) return;
      setState(() {
        _messages = history;
        _older = history.length == 40;
        _text.clear();
        _photo = null;
        _imagePath = null;
        _requestId = null;
      });
      _bottom();
      if (_mode == 'assist') {
        final navigation = (reply['actions'] as List? ?? [])
            .whereType<Map>()
            .where((a) => a['kind'] == 'navigate' && a['screen'] != 'payment');
        if (navigation.isNotEmpty) {
          await _navigate(Map<String, dynamic>.from(navigation.first));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectChat(String id) async {
    if (_busy) return;
    await _speech.cancel();
    _hold = false;
    setState(() {
      _busy = true;
      _error = null;
      _listening = false;
    });
    try {
      final rows = await _service.history(id);
      if (!mounted) return;
      setState(() {
        _conversation = id;
        _messages = rows;
        _older = rows.length == 40;
        _text.clear();
        _photo = null;
        _imagePath = null;
        _requestId = null;
        _photoCache.clear();
        _doneActions.clear();
      });
      _bottom();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _earlier() async {
    if (_busy || _conversation == null || _messages.isEmpty) return;
    setState(() => _busy = true);
    try {
      final rows = await _service.history(
        _conversation!,
        before: (_messages.first['id'] as num).toInt(),
      );
      if (mounted) {
        setState(() {
          _messages = [...rows, ..._messages];
          _older = rows.length == 40;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _newChat() {
    if (_busy) return;
    unawaited(_speech.cancel());
    _hold = false;
    setState(() {
      _conversation = null;
      _messages = [];
      _photo = null;
      _imagePath = null;
      _requestId = null;
      _text.clear();
      _error = null;
      _listening = false;
      _createId = CustomerTransactionService.newRequestId();
      _doneActions.clear();
      _photoCache.clear();
    });
  }

  Future<void> _history() async {
    if (_busy) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChatHistory(
        service: _service,
        onDeleted: (id) {
          if (mounted && id == _conversation) _newChat();
        },
      ),
    );
    if (!mounted) return;
    if (selected != null) {
      await _selectChat(selected);
    }
  }

  Future<void> _attach() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    try {
      Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!(source);
      } else {
        final file = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        bytes = await file?.readAsBytes();
      }
      if (bytes == null) return;
      final prepared = await _service.preparePhoto(bytes);
      if (mounted) {
        setState(() {
          _photo = prepared;
          _imagePath = null;
          _requestId = null;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startVoice() async {
    if (_busy || _voiceStarting || _listening) return;
    _hold = true;
    _voiceStarting = true;
    _voicePrefix = _text.text.trim();
    setState(() => _error = null);
    try {
      final available = await _speech.start(
        (words) {
          if (mounted) {
            _text.text = [
              _voicePrefix,
              words,
            ].where((s) => s.isNotEmpty).join(' ');
            _text.selection = TextSelection.collapsed(
              offset: _text.text.length,
            );
          }
        },
        () {
          if (mounted) setState(() => _listening = false);
        },
        () {
          if (mounted) {
            setState(() {
              _listening = false;
              _error =
                  'Voice input stopped. You can edit the text or type instead.';
            });
          }
        },
      );
      if (!mounted || !_hold) {
        await _speech.cancel();
        return;
      }
      setState(() {
        _listening = available;
        if (!available) {
          _error =
              'Microphone or speech recognition unavailable. Enable permissions in Settings, or type your message.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Voice input is unavailable. Please type your message.',
        );
      }
    } finally {
      _voiceStarting = false;
    }
  }

  Future<void> _stopVoice() async {
    _hold = false;
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  Future<void> _confirm(Map<String, dynamic> action) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(action['title']?.toString() ?? 'Confirm action'),
        content: SingleChildScrollView(
          child: Text(action['summary']?.toString() ?? ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _service.confirm(action['id'].toString());
      if (!mounted) return;
      setState(() => _doneActions.add(action['id'].toString()));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Action completed.')));
      if (result['booking_id'] != null) {
        await _navigate({
          'screen': 'booking',
          'record_id': result['booking_id'],
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigate(Map<String, dynamic> action) async {
    if (widget.onNavigate != null) {
      await widget.onNavigate!(action);
      return;
    }
    final id = action['record_id']?.toString();
    final valid = id != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id);
    final Widget? page = switch (action['screen']) {
      'explore' => const CustomerServiceListScreen(),
      'bookings' => const CustomerBookingsScreen(),
      'notifications' => const CustomerNotificationScreen(),
      'profile' => const CustomerProfileScreen(),
      'addresses' => const CustomerSavedAddressesScreen(),
      'reviews' => const CustomerMyReviewsScreen(),
      'booking' when valid => CustomerBookingDetailScreen(bookingId: id),
      'payment' when valid => CustomerCheckoutScreen(bookingId: id),
      'provider' when valid => CustomerProviderDetailScreen(
        providerId: id,
        heroTag: 'ai-$id',
      ),
      _ => null,
    };
    if (page != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }
  }

  Future<Uint8List> _loadPhoto(String path) {
    if (!_photoCache.containsKey(path) && _photoCache.length >= 8) {
      _photoCache.remove(_photoCache.keys.first);
    }
    return _photoCache.putIfAbsent(path, () => _service.photo(path));
  }

  Widget _photoView(String path) => FutureBuilder<Uint8List>(
    future: _loadPhoto(path),
    builder: (c, s) => s.hasData
        ? GestureDetector(
            onTap: () => showDialog(
              context: c,
              builder: (_) => Dialog(
                child: InteractiveViewer(child: Image.memory(s.data!)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                s.data!,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Text('Photo unavailable'),
              ),
            ),
          )
        : s.hasError
        ? TextButton(
            onPressed: () => setState(() => _photoCache.remove(path)),
            child: const Text('Retry photo'),
          )
        : const SizedBox(
            height: 50,
            child: Center(child: CircularProgressIndicator()),
          ),
  );
  Widget _bubble(Map<String, dynamic> row) {
    final user = row['role'] == 'user';
    final cards = (row['actions'] as List? ?? []).whereType<Map>();
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          color: user ? const Color(0xFFFFEBDD) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CustomerTheme.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user ? 'You' : 'Local Life AI',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: user
                    ? CustomerTheme.primaryDark
                    : const Color(0xFF7454B8),
              ),
            ),
            const SizedBox(height: 8),
            if (row['image_path'] != null)
              _photoView(row['image_path'].toString()),
            if ((row['content'] ?? '').toString().isNotEmpty)
              SelectableText(
                row['content'].toString(),
                style: const TextStyle(height: 1.5),
              ),
            ...cards.map((raw) {
              final a = Map<String, dynamic>.from(raw);
              final done =
                  _doneActions.contains(a['id']) || a['status'] == 'done';
              final expires = DateTime.tryParse(
                a['expires_at']?.toString() ?? '',
              );
              final expired =
                  !done &&
                  (a['status'] == 'expired' ||
                      (expires != null && expires.isBefore(DateTime.now())));
              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CustomerTheme.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a['title']?.toString() ?? 'Continue',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (a['summary'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(a['summary'].toString()),
                      ),
                    FilledButton.tonal(
                      onPressed: _busy || done || expired
                          ? null
                          : () => a['kind'] == 'navigate'
                                ? _navigate(a)
                                : _confirm(a),
                      child: Text(
                        done
                            ? 'Completed'
                            : expired
                            ? 'Expired — ask for a new card'
                            : a['kind'] == 'navigate'
                            ? 'Open'
                            : 'Review & confirm',
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: CustomerTheme.lightTheme,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close assistant',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          children: [
            Text('Local Life AI'),
            Text(
              'Your service companion',
              style: TextStyle(
                fontSize: 11,
                color: CustomerTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat history',
            onPressed: _busy ? null : _history,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: _busy ? null : _newChat,
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'chat',
                    label: Text('Ask AI'),
                    icon: Icon(Icons.chat_bubble_outline),
                  ),
                  ButtonSegment(
                    value: 'assist',
                    label: Text('Do it for me'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _busy
                    ? null
                    : (v) => setState(() => _mode = v.first),
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 28),
                        const Center(child: AiHalo(size: 70)),
                        const SizedBox(height: 22),
                        Text(
                          _mode == 'chat'
                              ? 'How can I help?'
                              : 'What would you like to do?',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Find the right service, compare providers or plan a booking.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CustomerTheme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ...(_mode == 'chat'
                                ? [
                                    'Help me choose a service',
                                    'Compare providers near my saved address',
                                    'What service does this photo need?',
                                  ]
                                : [
                                    'Help me book a service',
                                    'Show my upcoming bookings',
                                    'Change my default service address',
                                  ])
                            .map(
                              (p) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          _text.text = p;
                                        },
                                  style: OutlinedButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.all(16),
                                  ),
                                  child: Text(p),
                                ),
                              ),
                            ),
                        const SizedBox(height: 18),
                        const Text(
                          'Messages, attached photos and relevant app details are sent to Google Gemini. AI can make mistakes. Review action cards before confirming; payments stay with you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: CustomerTheme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_older ? 1 : 0),
                      itemBuilder: (_, index) {
                        if (_older && index == 0) {
                          return TextButton(
                            onPressed: _busy ? null : _earlier,
                            child: const Text('Load earlier messages'),
                          );
                        }
                        return _bubble(_messages[index - (_older ? 1 : 0)]);
                      },
                    ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Working on your request…',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF1E8),
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFF9A3412),
                    fontSize: 12,
                  ),
                ),
              ),
            if (_photo != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          _photo!,
                          height: 65,
                          width: 65,
                          fit: BoxFit.cover,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove photo',
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _photo = null;
                                _imagePath = null;
                                _requestId = null;
                              }),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            if (_listening)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Listening… release to edit your words',
                  style: TextStyle(color: CustomerTheme.primary),
                ),
              ),
            Padding(
              key: const ValueKey('ai-composer'),
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attach photo',
                    onPressed: _busy ? null : _attach,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_busy,
                      onChanged: (_) {
                        if (!_listening) unawaited(_speech.cancel());
                      },
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      decoration: InputDecoration(
                        hintText: _mode == 'chat'
                            ? 'Ask anything about services…'
                            : 'Tell me what to do…',
                        counterText: '',
                        contentPadding: const EdgeInsets.all(13),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  Semantics(
                    label: 'Hold to speak; tap to start or stop',
                    button: true,
                    child: Tooltip(
                      message: 'Hold to speak',
                      triggerMode: TooltipTriggerMode.manual,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _busy
                            ? null
                            : () => _listening ? _stopVoice() : _startVoice(),
                        onLongPressStart: _busy ? null : (_) => _startVoice(),
                        onLongPressEnd: (_) => _stopVoice(),
                        onLongPressCancel: () => _stopVoice(),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            _listening ? Icons.stop_circle : Icons.mic_none,
                            color: _listening ? CustomerTheme.primary : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
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

class AiHalo extends StatelessWidget {
  final double size;
  const AiHalo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: [Color(0xFFFF9752), Color(0xFFAA78D6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFAA78D6).withValues(alpha: .22),
          blurRadius: 14,
          spreadRadius: 3,
        ),
      ],
    ),
    child: Icon(
      Icons.auto_awesome_rounded,
      color: Colors.white,
      size: size * .56,
    ),
  );
}

class _ChatHistory extends StatefulWidget {
  final CustomerAiService service;
  final ValueChanged<String> onDeleted;
  const _ChatHistory({required this.service, required this.onDeleted});
  @override
  State<_ChatHistory> createState() => _ChatHistoryState();
}

class _ChatHistoryState extends State<_ChatHistory> {
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final rows = await widget.service.conversations(offset: _rows.length);
      if (mounted) {
        setState(() {
          _rows.addAll(rows);
          _more = rows.length == 30;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load chats.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: const Text(
          'Its conversation history and attached photos will be removed. Bookings already submitted are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep chat'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.delete(row['id'].toString());
      widget.onDeleted(row['id'].toString());
      if (mounted) setState(() => _rows.remove(row));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Could not delete chat. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Your conversations',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            TextButton(
              onPressed: _loading ? null : _load,
              child: Text('$_error Retry'),
            ),
          Expanded(
            child: ListView(
              children: [
                if (_rows.isEmpty && !_loading)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text('Your chats will appear here.'),
                  ),
                ..._rows.map(
                  (r) => ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      r['title'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: _loading
                        ? null
                        : () => Navigator.pop(context, r['id'].toString()),
                    trailing: IconButton(
                      tooltip: 'Delete chat',
                      onPressed: _loading ? null : () => _delete(r),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
                if (_more && _rows.isNotEmpty)
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Load more chats'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
