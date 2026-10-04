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
  const ConversationScreen({
    super.key,
    this.conversationId,
    this.providerId,
    this.bookingId,
    this.service,
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
  int _clearedThrough = 0;
  bool _loading = true,
      _sending = false,
      _canSend = false,
      _blocked = false,
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
        _blocked = data['blocked'] == true;
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

  Future<void> _send() async {
    final body = _text.text.trim();
    if (_sending || !_canSend || _id == null) return;
    if (body.isEmpty || body.length > 2000) {
      await CustomerDialogs.show(
        context,
        message: 'Enter a message of 1–2000 characters.',
      );
      return;
    }
    if (_retryBody != body) {
      _retryBody = body;
      _retryId = CustomerTransactionService.newRequestId();
    }
    setState(() => _sending = true);
    try {
      final message = await _service.send(_id!, body, _retryId!);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m['message_id'] == message['message_id'])) {
          _messages.insert(0, message);
        }
        _text.clear();
        _retryBody = null;
        _retryId = null;
      });
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        await CustomerDialogs.error(context, e);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (_id == null) return;
    final action = _blocked ? 'Unblock' : 'Block';
    if (!await CustomerDialogs.confirm(
      context,
      title: '$action conversation?',
      message: _blocked
          ? 'Both participants will be able to send messages again.'
          : 'Neither participant can send messages until you unblock this chat. Your bookings stay unchanged.',
    )) {
      return;
    }
    try {
      await _service.manage(_id!, _blocked ? 'unblock' : 'block');
      await _refresh();
      if (mounted) {
        await CustomerDialogs.show(
          context,
          message: 'Conversation ${_blocked ? 'blocked' : 'unblocked'}.',
        );
      }
    } catch (e) {
      if (mounted) await CustomerDialogs.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: CustomerTheme.lightTheme,
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _toggleBlock(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'block',
                child: Text(_blocked ? 'Unblock' : 'Block'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Discuss a time here, then submit a booking. Pay only after the provider accepts it.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: _id == null ? _start : _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomerRefresh(
                      onRefresh: _id == null ? _start : _refresh,
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.isEmpty
                            ? 1
                            : _messages.length + (_more ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_messages.isEmpty)
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: Text('Start the conversation.'),
                              ),
                            );
                          if (index == _messages.length) {
                            return TextButton(
                              onPressed: _olderLoading ? null : _older,
                              child: Text(
                                _olderLoading
                                    ? 'Loading…'
                                    : 'Load earlier messages',
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
                                  SelectableText(m['body'].toString()),
                                  const SizedBox(height: 4),
                                  if (date != null)
                                    Text(
                                      DateFormat('d MMM, HH:mm').format(date),
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
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Messaging is unavailable. Check the block setting or refresh this conversation.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: _canSend && !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send message',
                    onPressed: _canSend && !_sending ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: CustomerTheme.primary),
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
