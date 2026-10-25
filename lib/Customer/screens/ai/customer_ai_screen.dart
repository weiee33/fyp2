import '../../widgets/customer_dialogs.dart';
import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import '../../widgets/customer_menu.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:intl/intl.dart';
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
import '../../agent/agent_host.dart';

class CustomerAiScreen extends StatefulWidget {
  final CustomerAiService? service;
  final CustomerAiSpeech? speech;
  final Future<Uint8List?> Function(ImageSource)? pickPhoto;
  final Future<void> Function(Map<String, dynamic>)? onNavigate;
  final Future<void> Function(String)? onStartAgent;
  const CustomerAiScreen({
    super.key,
    this.service,
    this.speech,
    this.pickPhoto,
    this.onNavigate,
    this.onStartAgent,
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
  String _chatTitle = 'New chat';
  Map<String, dynamic>? _pendingMessage;
  bool _sending = false;
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
    final message = _text.text.trim();
    if (message.length > 4000) {
      setState(() => _error = 'Keep your message under 4000 characters.');
      return;
    }
    if (_mode == 'assist') {
      if (_photo != null) {
        setState(() => _error = 'Use AI chat to ask about an attached photo.');
        return;
      }
      await _startAgent(message);
      return;
    }
    if (_requestId == null || _retryText != message || _retryMode != _mode) {
      _requestId = CustomerTransactionService.newRequestId();
      _retryText = message;
      _retryMode = _mode;
    }
    setState(() {
      _busy = true;
      _sending = true;
      _pendingMessage = {
        'role': 'user',
        'content': message,
        if (_photo != null) 'local_photo': _photo,
      };
      _text.clear();
      _error = null;
      _listening = false;
    });
    _bottom();
    try {
      await _speech.cancel();
      _hold = false;
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
      List<Map<String, dynamic>> history;
      try {
        history = await _service.history(_conversation!);
      } catch (_) {
        // A saved reply must remain visible even if the history refresh fails.
        history = [
          ..._messages,
          {
            ...?_pendingMessage,
            if (_imagePath != null) 'image_path': _imagePath,
          },
          reply,
        ];
      }
      if (!mounted) return;
      setState(() {
        _messages = history;
        _pendingMessage = null;
        if (_chatTitle == 'New chat') {
          _chatTitle = message.isEmpty
              ? 'Photo conversation'
              : message.substring(0, math.min(70, message.length));
        }
        _older = history.length == 40;
        _text.clear();
        _photo = null;
        _imagePath = null;
        _requestId = null;
      });
      _bottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _message(e);
          _text.text = message;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _sending = false;
        });
      }
    }
  }

  Future<void> _startAgent(String goal) async {
    final controller = AgentHost.of(context);
    if (controller == null && widget.onStartAgent == null) {
      setState(
        () => _error = 'Open AI Agent from the customer navigation bar.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _speech.cancel();
      if (!mounted) return;
      _conversation ??= (await _service.create(_createId))['id'].toString();
      final conversation = _conversation!, service = _service;
      controller?.setRecorder(
        (event, kind, text) =>
            service.recordAgentEvent(conversation, event, kind, text),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
      return;
    }
    if (!mounted) return;
    final callback = widget.onStartAgent;
    Navigator.pop(context);
    if (callback != null) {
      unawaited(callback(goal));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      unawaited(controller!.run(goal));
    }
  }

  Future<void> _selectChat(String id, {String title = 'Conversation'}) async {
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
        _chatTitle = title;
        _pendingMessage = null;
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
      _chatTitle = 'New chat';
      _pendingMessage = null;
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
    final selected = await showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('Close chat history'),
      barrierColor: Colors.black.withValues(alpha: .25),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
      pageBuilder: (c, _, _) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: math.min(420, MediaQuery.sizeOf(c).width - 32),
          height: math.min(720, MediaQuery.sizeOf(c).height * .82),
          child: Material(
            color: const Color(0xFFFAF9F7),
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: CustomerActionTheme(
              child: _ChatHistory(
                service: _service,
                currentId: _conversation,
                onRenamed: (id, title) {
                  if (mounted && id == _conversation) {
                    setState(() => _chatTitle = title);
                  }
                },
                onDeleted: (id) {
                  if (mounted && id == _conversation) _newChat();
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected['new'] == true) {
      _newChat();
      return;
    }
    await _selectChat(
      selected['id'].toString(),
      title: selected['title'].toString(),
    );
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
              title: Text(tr('Choose from gallery')),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(tr('Take a photo')),
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
    final booking = action['kind'] == 'booking';
    final ok = await showCustomerDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          tr(
            booking
                ? 'Review booking'
                : action['title']?.toString() ?? 'Confirm action',
          ),
        ),
        content: SingleChildScrollView(
          physics: customerScrollPhysics(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(actionSummary(action)),
              if (booking) ...[
                const SizedBox(height: 16),
                Text(
                  tr(
                    'Confirm these details to send your request. You can pay after the provider accepts.',
                  ),
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Not now')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr(booking ? 'Send booking request' : 'Confirm')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              booking
                  ? 'Booking request sent. Payment opens after provider acceptance.'
                  : 'Action completed.',
            ),
          ),
        ),
      );
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

  Future<void> _openBooking(Map<String, dynamic> action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Completed action confirmation is idempotent and returns its original
      // booking ID. Fetch current eligibility instead of using that old snapshot.
      final result = await _service.confirm(action['id'].toString());
      final id = result['booking_id']?.toString();
      if (id == null) {
        throw const FormatException(
          'This booking could not be opened. Please check My bookings.',
        );
      }
      final booking = await _service.booking(id);
      if (!mounted) return;
      await _navigate({
        'screen': booking['can_pay'] == true ? 'payment' : 'booking',
        'record_id': id,
      });
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
            onTap: () => showCustomerDialog(
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
                errorBuilder: (_, _, _) => Text(tr('Photo unavailable')),
              ),
            ),
          )
        : s.hasError
        ? TextButton(
            onPressed: () => setState(() => _photoCache.remove(path)),
            child: Text(tr('Retry photo')),
          )
        : const SizedBox(
            height: 50,
            child: Center(child: CircularProgressIndicator()),
          ),
  );
  TextSpan _replyText(String text) {
    final plain = text.replaceAllMapped(
      RegExp(r'^(\s*)\* ', multiLine: true),
      (m) => '${m[1]}• ',
    );
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in RegExp(r'\*\*([^*\n]+)\*\*').allMatches(plain)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: plain.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: match[1],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
      offset = match.end;
    }
    spans.add(TextSpan(text: plain.substring(offset)));
    return TextSpan(children: spans);
  }

  Widget _bubble(Map<String, dynamic> row) {
    final user = row['role'] == 'user';
    final cards = (row['actions'] as List? ?? []).whereType<Map>();
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: math.min(
            620,
            MediaQuery.sizeOf(context).width * (user ? .83 : .91),
          ),
        ),
        decoration: BoxDecoration(
          color: user ? const Color(0xFFFFEBDD) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CustomerTheme.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                user
                    ? 'You'
                    : row['origin'] == 'agent'
                    ? 'AI Agent'
                    : 'Local Life Service Assistant AI',
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: user || row['origin'] == 'agent'
                    ? CustomerTheme.primaryDark
                    : const Color(0xFF7454B8),
              ),
            ),
            const SizedBox(height: 8),
            if (row['local_photo'] is Uint8List)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  row['local_photo'] as Uint8List,
                  height: 130,
                  fit: BoxFit.cover,
                ),
              ),
            if (row['image_path'] != null && row['local_photo'] == null)
              _photoView(row['image_path'].toString()),
            if ((row['content'] ?? '').toString().isNotEmpty)
              SelectableText.rich(
                user
                    ? TextSpan(text: row['content'].toString())
                    : _replyText(row['content'].toString()),
                style: const TextStyle(height: 1.5),
              ),
            ...cards.map((raw) {
              final a = Map<String, dynamic>.from(raw);
              final done =
                  _doneActions.contains(a['id']) || a['status'] == 'done';
              final booking = a['kind'] == 'booking';
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
                      tr(
                        booking
                            ? (done
                                  ? 'Booking request sent'
                                  : 'Your booking review')
                            : a['title']?.toString() ?? 'Continue',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (a['summary'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(actionSummary(a)),
                      ),
                    if (booking)
                      Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          tr('Review & send → Provider accepts → You pay'),
                          style: TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                    FilledButton.tonal(
                      onPressed: _busy || (done && !booking) || expired
                          ? null
                          : () => done && booking
                                ? _openBooking(a)
                                : a['kind'] == 'navigate'
                                ? _navigate(a)
                                : _confirm(a),
                      child: Text(
                        tr(
                          done
                              ? (booking
                                    ? 'View booking & payment'
                                    : 'Completed')
                              : expired
                              ? 'Expired — ask for a new card'
                              : a['kind'] == 'navigate'
                              ? 'Open'
                              : booking
                              ? 'Review booking'
                              : 'Review & confirm',
                        ),
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

  Widget _voiceButton() => Semantics(
    label: tr('Hold to speak; tap to start or stop'),
    button: true,
    child: Tooltip(
      message: tr('Hold to speak'),
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : () => _listening ? _stopVoice() : _startVoice(),
        onLongPressStart: _busy ? null : (_) => _startVoice(),
        onLongPressEnd: (_) => _stopVoice(),
        onLongPressCancel: _stopVoice,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            _listening ? Icons.stop_circle : Icons.graphic_eq_rounded,
            color: _listening
                ? CustomerTheme.primary
                : CustomerTheme.textSecondary,
          ),
        ),
      ),
    ),
  );

  Widget _composer() => Container(
    key: const ValueKey('ai-composer'),
    margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
    padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F0EE),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xFFE5E2DE)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_photo != null && !_sending)
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _photo!,
                  height: 58,
                  width: 58,
                  fit: BoxFit.cover,
                ),
              ),
              IconButton(
                tooltip: trOrNull('Remove photo'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _photo = null;
                        _imagePath = null;
                        _requestId = null;
                      }),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        TextField(
          controller: _text,
          enabled: !_busy,
          onChanged: (_) {
            if (!_listening) unawaited(_speech.cancel());
          },
          minLines: 1,
          maxLines: 4,
          maxLength: 4000,
          decoration: InputDecoration(
            hintText: trOrNull('Message or hold to speak'),
            counterText: '',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: CustomerMenu<String>(
                  tooltip: trOrNull('Assistant mode'),
                  initialValue: _mode,
                  enabled: !_busy,
                  onSelected: (mode) => setState(() => _mode = mode),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'chat',
                      child: CustomerMenuRow(
                        label: tr('AI Chat'),
                        showCheck: false,
                        selected: _mode == 'chat',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'assist',
                      child: CustomerMenuRow(
                        label: tr('AI Agent'),
                        showCheck: false,
                        selected: _mode == 'assist',
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_outlined,
                          size: 16,
                          color: CustomerTheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            tr(_mode == 'chat' ? 'AI Chat' : 'AI Agent'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: trOrNull('Attach photo'),
              onPressed: _busy ? null : _attach,
              icon: const Icon(Icons.add_circle_outline),
              visualDensity: VisualDensity.compact,
            ),
            _voiceButton(),
            IconButton.filled(
              tooltip: trOrNull('Send message'),
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.arrow_upward_rounded),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _welcome() => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      physics: customerScrollPhysics(context),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(0, bounds.maxHeight - 48),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AiHalo(size: 56),
            const SizedBox(height: 24),
            Text(
              tr('What can I help you\nwith today?'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in const [
                  (
                    'Find a service',
                    'Help me choose a service',
                    Icons.search_rounded,
                  ),
                  (
                    'Nearby providers',
                    'Compare providers near my saved address',
                    Icons.near_me_outlined,
                  ),
                  (
                    'Help with a photo',
                    'What service does this photo need?',
                    Icons.image_outlined,
                  ),
                ])
                  ActionChip(
                    avatar: Icon(
                      item.$3,
                      size: 16,
                      color: CustomerTheme.primary,
                    ),
                    label: Text(
                      tr(item.$1),
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFEAE7E3)),
                    onPressed: _busy
                        ? null
                        : () {
                            _text.text = tr(item.$2);
                          },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _conversationList() => ListView.builder(
    physics: customerScrollPhysics(context),
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    itemCount:
        _messages.length +
        (_older && _messages.isNotEmpty ? 1 : 0) +
        (_pendingMessage != null ? 1 : 0) +
        (_sending ? 1 : 0),
    itemBuilder: (_, index) {
      if (_older && _messages.isNotEmpty) {
        if (index == 0) {
          return TextButton(
            onPressed: _busy ? null : _earlier,
            child: Text(tr('Load earlier messages')),
          );
        }
        index--;
      }
      if (index < _messages.length) return _bubble(_messages[index]);
      index -= _messages.length;
      if (_pendingMessage != null && index == 0) {
        return _bubble(_pendingMessage!);
      }
      return const _ThinkingBubble();
    },
  );

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Theme(
      data: CustomerTheme.lightTheme,
      child: CustomerScaffold(
        backgroundColor: const Color(0xFFFCFBF9),
        appBar: AppBar(
          toolbarHeight: 88,
          backgroundColor: const Color(0xFFFCFBF9),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: trOrNull('Chat history'),
            onPressed: _busy ? null : _history,
            icon: const Icon(Icons.menu_rounded),
          ),
          centerTitle: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                tr('Local Life Service Assistant AI'),
                textAlign: TextAlign.center,
                maxLines: 3,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                _conversation == null ? tr(_chatTitle) : _chatTitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: CustomerTheme.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: trOrNull('Close assistant'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_busy && !_sending)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _messages.isEmpty && _pendingMessage == null
                    ? _welcome()
                    : _conversationList(),
              ),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEFE5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Color(0xFF9A3412),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(_error!),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9A3412),
                          ),
                        ),
                      ),
                      if (_pendingMessage != null)
                        TextButton(
                          onPressed: _busy ? null : _send,
                          child: Text(tr('Retry')),
                        ),
                    ],
                  ),
                ),
              if (_listening)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    tr('Listening… release to edit your words'),
                    style: TextStyle(
                      fontSize: 12,
                      color: CustomerTheme.primary,
                    ),
                  ),
                ),
              _composer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: GestureDetector(
                  onTap: () => showCustomerDialog<void>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(tr('Using Local Life Service Assistant AI')),
                      content: Text(
                        tr(
                          'Messages, attached photos and relevant app details are sent to Google Gemini. AI can make mistakes. Review action cards before confirming; payments stay with you.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: Text(tr('Got it')),
                        ),
                      ],
                    ),
                  ),
                  child: Text(
                    tr('Powered by Gemini · AI can make mistakes · Privacy'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: CustomerTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();
  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Semantics(
      liveRegion: true,
      label: tr('AI is thinking'),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const ValueKey('ai-thinking-bubble'),
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFEAE7E3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Local Life Service Assistant AI'),
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7454B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (_, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        3,
                        (i) => Opacity(
                          opacity:
                              .3 +
                              .7 *
                                  ((math.sin(
                                            _animation.value * 2 * math.pi -
                                                i * .8,
                                          ) +
                                          1) /
                                      2),
                          child: Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: const BoxDecoration(
                              color: Color(0xFF9C7BC6),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    tr('Thinking…'),
                    style: TextStyle(
                      fontSize: 13,
                      color: CustomerTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches the orange assistant entry point in customer navigation.
class AiHalo extends StatelessWidget {
  final double size;
  const AiHalo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: CustomerTheme.primary,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [
        BoxShadow(
          color: CustomerTheme.primary.withValues(alpha: .22),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Icon(
      Icons.auto_awesome_rounded,
      color: Colors.white,
      size: size * .54,
    ),
  );
}

class _ChatHistory extends StatefulWidget {
  final CustomerAiService service;
  final String? currentId;
  final ValueChanged<String> onDeleted;
  final void Function(String, String) onRenamed;
  const _ChatHistory({
    required this.service,
    required this.onDeleted,
    required this.onRenamed,
    this.currentId,
  });
  @override
  State<_ChatHistory> createState() => _ChatHistoryState();
}

class _ChatHistoryState extends State<_ChatHistory> {
  final List<Map<String, dynamic>> _rows = [];
  final _search = TextEditingController();
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Active chats are capped at 100; load all pages so search is complete.
      final all = <Map<String, dynamic>>[];
      for (var page = 0; page < 4; page++) {
        final rows = await widget.service.conversations(offset: page * 30);
        all.addAll(rows);
        if (rows.length < 30) break;
      }
      if (mounted) {
        setState(() {
          _rows
            ..clear()
            ..addAll(all);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load chats.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rename(Map<String, dynamic> row) async {
    final title = await showCustomerDialog<String>(
      context: context,
      builder: (_) => _RenameChatDialog(
        service: widget.service,
        id: row['id'].toString(),
        title: row['title'].toString(),
      ),
    );
    if (title == null || !mounted) return;
    setState(() => row['title'] = title);
    widget.onRenamed(row['id'].toString(), title);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final yes = await showCustomerDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Delete this chat?')),
        content: Text(
          tr(
            'Its conversation history and attached photos will be removed. Bookings already submitted are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Keep chat')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Delete')),
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

  String _group(Map<String, dynamic> row) {
    final date = DateTime.tryParse(
      row['updated_at']?.toString() ?? '',
    )?.toLocal();
    if (date == null) return 'Conversations';
    final now = DateTime.now(), today = DateTime.now();
    if (DateUtils.isSameDay(date, today)) return 'Today';
    if (DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('MMMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final query = _search.text.trim().toLowerCase();
    final rows = _rows
        .where((r) => r['title'].toString().toLowerCase().contains(query))
        .toList();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Your Chats'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: trOrNull('Close chat history'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: trOrNull('Search chats'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: trOrNull('Clear search'),
                        onPressed: () => setState(() => _search.clear()),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextButton.icon(
              onPressed: _loading
                  ? null
                  : () => Navigator.pop(context, {'new': true}),
              icon: const Icon(Icons.edit_square, size: 18),
              label: Text(tr('New chat')),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: _loading ? null : _load,
                child: Text(tr("{0} Retry", [_error])),
              ),
            ),
          Expanded(
            child: ListView.builder(
              physics: customerScrollPhysics(context),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: rows.isEmpty ? 1 : rows.length,
              itemBuilder: (_, i) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      tr(
                        _loading
                            ? 'Loading conversations…'
                            : query.isEmpty
                            ? 'Your chats will appear here.'
                            : 'No chats match your search.',
                      ),
                      style: const TextStyle(
                        color: CustomerTheme.textSecondary,
                      ),
                    ),
                  );
                }
                final row = rows[i], group = _group(rows[i]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (i == 0 || _group(rows[i - 1]) != group)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                        child: Text(
                          tr(group),
                          style: const TextStyle(
                            fontSize: 12,
                            color: CustomerTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      selected: widget.currentId == row['id'],
                      selectedTileColor: const Color(0xFFECE8E3),
                      contentPadding: const EdgeInsets.only(left: 12, right: 4),
                      title: Text(
                        row['title'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: _loading
                          ? null
                          : () => Navigator.pop(context, row),
                      trailing: CustomerMenu<String>(
                        tooltip: trOrNull('Chat options'),
                        enabled: !_loading,
                        icon: const Icon(Icons.more_horiz, size: 20),
                        onSelected: (value) =>
                            value == 'rename' ? _rename(row) : _delete(row),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: CustomerMenuRow(
                              icon: Icons.edit_outlined,
                              label: tr('Rename'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: CustomerMenuRow(
                              icon: Icons.delete_outline,
                              label: tr('Delete'),
                              destructive: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                AiHalo(size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Local Life Service Assistant AI'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RenameChatDialog extends StatefulWidget {
  final CustomerAiService service;
  final String id, title;
  const _RenameChatDialog({
    required this.service,
    required this.id,
    required this.title,
  });
  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  late final _name = TextEditingController(text: widget.title);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _name.text.trim();
    if (title.isEmpty || title.length > 70) {
      setState(() => _error = 'Enter a name between 1 and 70 characters.');
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.rename(widget.id, title);
      if (mounted) Navigator.pop(context, title);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not rename this chat. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(tr('Rename chat')),
        content: TextField(
          controller: _name,
          autofocus: true,
          enabled: !_saving,
          maxLength: 70,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: trOrNull('Chat name'),
            errorText: trOrNull(_error),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(tr(_saving ? 'Saving…' : 'Save')),
          ),
        ],
      ),
    );
  }
}
