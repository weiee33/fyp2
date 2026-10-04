import '../../Customer/widgets/customer_refresh.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../Customer/core/customer_theme.dart';
import '../../Customer/widgets/customer_dialogs.dart';
import 'chat_service.dart';
import 'chat_screen.dart';

class ChatInboxScreen extends StatefulWidget {
  final bool customer;
  final ChatService? service;
  const ChatInboxScreen({super.key, this.customer = true, this.service});
  @override
  State<ChatInboxScreen> createState() => _InboxState();
}

class _InboxState extends State<ChatInboxScreen> {
  late final _service = widget.service ?? ChatService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _chats = [], _providers = [];
  bool _loading = true, _more = false, _paging = false, _blockedOnly = false;
  String? _error;
  int _generation = 0;
  Timer? _debounce;
  ChatUpdates? _updates;
  @override
  void initState() {
    super.initState();
    _load();
    _updates = ChatUpdates(_service, _load);
  }

  @override
  void dispose() {
    _generation++;
    _updates?.dispose();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final version = ++_generation, query = _search.text.trim();
    try {
      final results = await Future.wait([
        _blockedOnly
            ? _service.blocked(keyword: query)
            : _service.inbox(keyword: query),
        if (widget.customer && !_blockedOnly && query.isNotEmpty)
          _service.search(query),
      ]);
      if (!mounted || version != _generation) return;
      setState(() {
        _chats = results[0];
        _providers = results.length > 1 ? results[1] : [];
        _more = _chats.length == 30;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted && version == _generation) {
        final notify = _error != CustomerDialogs.errorMessage(e);
        setState(() {
          _error = CustomerDialogs.errorMessage(e);
          _loading = false;
        });
        if (notify) CustomerDialogs.error(context, e);
      }
    }
  }

  Future<void> _next() async {
    if (_paging) return;
    final version = _generation;
    setState(() => _paging = true);
    try {
      final rows = await (_blockedOnly
          ? _service.blocked(
              keyword: _search.text.trim(),
              offset: _chats.length,
            )
          : _service.inbox(
              keyword: _search.text.trim(),
              offset: _chats.length,
            ));
      if (mounted && version == _generation) {
        setState(() {
          final ids = _chats.map((c) => c['conversation_id']).toSet();
          _chats.addAll(rows.where((c) => !ids.contains(c['conversation_id'])));
          _more = rows.length == 30;
        });
      }
    } catch (e) {
      if (mounted) await CustomerDialogs.error(context, e);
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  Future<void> _open({String? conversationId, String? providerId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversationId: conversationId,
          providerId: providerId,
          service: _service,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _manage(Map<String, dynamic> row, String action) async {
    if (action == 'delete' &&
        !await CustomerDialogs.confirm(
          context,
          title: 'Delete this chat?',
          message:
              'This clears the chat from your inbox and your visible history. The other person keeps their copy. A new message will reopen the conversation.',
        )) {
      return;
    }
    try {
      await _service.manage(row['conversation_id'] as String, action);
      await _load();
      if (mounted) {
        await CustomerDialogs.show(
          context,
          message: action == 'delete'
              ? 'Chat deleted from your inbox.'
              : action == 'pin'
              ? 'Chat pinned.'
              : 'Chat unpinned.',
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
        title: Text(_blockedOnly ? 'Blocked chats' : 'Chats'),
        actions: [
          IconButton(
            tooltip: _blockedOnly ? 'All chats' : 'Blocked chats',
            onPressed: () {
              setState(() {
                _blockedOnly = !_blockedOnly;
                _loading = true;
              });
              _load();
            },
            icon: Icon(_blockedOnly ? Icons.chat_bubble_outline : Icons.block),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: widget.customer
                    ? 'Search provider name'
                    : 'Search customer name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                ),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              },
            ),
          ),
          Expanded(
            child: CustomerRefresh(
              onRefresh: _load,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                children: [
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    ListTile(
                      title: Text(_error!),
                      trailing: TextButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  if (!_loading && _error == null && _chats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _blockedOnly
                            ? 'No blocked conversations.'
                            : widget.customer
                            ? 'No conversations yet. Search a provider by name to start chatting.'
                            : 'No conversations yet. Customers can contact you from your provider page.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final chat in _chats)
                    _SwipeChatRow(
                      key: ValueKey(chat['conversation_id']),
                      row: chat,
                      onOpen: () =>
                          _open(conversationId: chat['conversation_id']),
                      onAction: (action) => _manage(chat, action),
                    ),
                  if (_more)
                    TextButton(
                      onPressed: _paging ? null : _next,
                      child: Text(
                        _paging ? 'Loading…' : 'Load more conversations',
                      ),
                    ),
                  if (widget.customer &&
                      !_blockedOnly &&
                      _search.text.trim().isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Find providers',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (!_loading && _providers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No verified providers match this name.'),
                      ),
                    for (final provider in _providers)
                      ListTile(
                        tileColor: Colors.white,
                        leading: const CircleAvatar(
                          child: Icon(Icons.home_repair_service_outlined),
                        ),
                        title: Text(provider['business_name'].toString()),
                        subtitle: Text(provider['city']?.toString() ?? ''),
                        trailing: const Icon(Icons.chat_bubble_outline),
                        onTap: () => _open(providerId: provider['provider_id']),
                      ),
                    if (_providers.length == 30)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Showing the first 30 providers. Refine the name to find a specific provider.',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SwipeChatRow extends StatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onOpen;
  final Future<void> Function(String) onAction;
  const _SwipeChatRow({
    super.key,
    required this.row,
    required this.onOpen,
    required this.onAction,
  });
  @override
  State<_SwipeChatRow> createState() => _SwipeChatState();
}

class _SwipeChatState extends State<_SwipeChatRow> {
  bool _revealed = false, _busy = false;
  Future<void> _act(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onAction(action);
    if (mounted) {
      setState(() {
        _busy = false;
        _revealed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinned = widget.row['pinned'] == true,
        unread = (widget.row['unread_count'] as num?)?.toInt() ?? 0;
    final pinAction = pinned ? 'unpin' : 'pin';
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 76,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      shape: const RoundedRectangleBorder(),
                    ),
                    onPressed: _busy ? null : () => _act(pinAction),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.push_pin_outlined),
                        Text(
                          pinned ? 'Unpin' : 'Pin',
                          maxLines: 1,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 76,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: Colors.red,
                      shape: const RoundedRectangleBorder(),
                    ),
                    onPressed: _busy ? null : () => _act('delete'),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline),
                        Text(
                          'Delete',
                          maxLines: 1,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            transform: Matrix4.translationValues(_revealed ? -152 : 0, 0, 0),
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0).abs() > 60) {
                  setState(() => _revealed = d.primaryVelocity! < 0);
                }
              },
              onHorizontalDragUpdate: (d) {
                if (d.delta.dx.abs() > 3) {
                  setState(() => _revealed = d.delta.dx < 0);
                }
              },
              child: Material(
                color: pinned ? CustomerTheme.primarySurface : Colors.white,
                child: ListTile(
                  onTap: _revealed
                      ? () => setState(() => _revealed = false)
                      : widget.onOpen,
                  leading: CircleAvatar(
                    backgroundColor: CustomerTheme.primarySurface,
                    child: Icon(
                      widget.row['blocked'] == true
                          ? Icons.block
                          : Icons.person_outline,
                      color: CustomerTheme.primary,
                    ),
                  ),
                  title: Text(
                    widget.row['peer_name'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: unread > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    widget.row['preview']?.toString() ?? 'Start a conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pinned) const Icon(Icons.push_pin, size: 16),
                      if (unread > 0)
                        Badge(label: Text(unread > 99 ? '99+' : '$unread')),
                      PopupMenuButton<String>(
                        tooltip: 'Chat actions',
                        onSelected: _act,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: pinAction,
                            child: Text(
                              pinned ? 'Unpin' : 'Pin',
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
