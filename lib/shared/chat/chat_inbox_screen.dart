import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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
  bool _loading = true, _more = false, _paging = false;
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
        _service.inbox(keyword: query),
        if (widget.customer && query.isNotEmpty) _service.search(query),
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
      final rows = await _service.inbox(
        keyword: _search.text.trim(),
        offset: _chats.length,
      );
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
          customer: widget.customer,
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
          title: tr('Delete this chat?'),
          message: tr(
            'This clears the chat from your inbox and your visible history. The other person keeps their copy. A new message will reopen the conversation.',
          ),
        )) {
      return;
    }
    try {
      await _service.manage(row['conversation_id'] as String, action);
      await _load();
      if (mounted) {
        await CustomerDialogs.show(
          context,
          message: tr(
            action == 'delete'
                ? 'Chat deleted from your inbox.'
                : action == 'pin'
                ? 'Chat pinned.'
                : 'Chat unpinned.',
          ),
        );
      }
    } catch (e) {
      if (mounted) await CustomerDialogs.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Theme(
      data: CustomerTheme.lightTheme,
      child: CustomerScaffold(
        enabled: widget.customer,
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(title: Text(tr('Chats'))),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: trOrNull(
                    widget.customer
                        ? 'Search provider name'
                        : 'Search customer name',
                  ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: trOrNull('Clear search'),
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
                customer: widget.customer,
                onRefresh: _load,
                child: ListView(
                  physics: widget.customer
                      ? customerScrollPhysics(context)
                      : const ClampingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                  children: [
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                    if (_error != null)
                      ListTile(
                        title: Text(tr(_error!)),
                        trailing: TextButton(
                          onPressed: _load,
                          child: Text(tr('Retry')),
                        ),
                      ),
                    if (!_loading && _error == null && _chats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr(
                            widget.customer
                                ? 'No conversations yet. Search a provider by name to start chatting.'
                                : 'No conversations yet. Customers can contact you from your provider page.',
                          ),
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
                          tr(_paging ? 'Loading…' : 'Load more conversations'),
                        ),
                      ),
                    if (widget.customer && _search.text.trim().isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          tr('Find providers'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (!_loading && _providers.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            tr('No verified providers match this name.'),
                          ),
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
                          onTap: () =>
                              _open(providerId: provider['provider_id']),
                        ),
                      if (_providers.length == 30)
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            tr(
                              'Showing the first 30 providers. Refine the name to find a specific provider.',
                            ),
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
  bool _busy = false;
  Future<void> _act(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onAction(action);
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final pinned = widget.row['pinned'] == true,
        unread = (widget.row['unread_count'] as num?)?.toInt() ?? 0;
    final pinAction = pinned ? 'unpin' : 'pin';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Slidable(
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: .5,
            children: [
              SlidableAction(
                borderRadius: BorderRadius.circular(16),
                onPressed: _busy ? null : (_) => _act(pinAction),
                backgroundColor: CustomerTheme.primary,
                foregroundColor: Colors.white,
                icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: tr(pinned ? 'Unpin' : 'Pin'),
              ),
              SlidableAction(
                borderRadius: BorderRadius.circular(16),
                onPressed: _busy ? null : (_) => _act('delete'),
                backgroundColor: CustomerTheme.danger,
                foregroundColor: Colors.white,
                icon: Icons.delete_outline,
                label: tr('Delete'),
              ),
            ],
          ),
          child: Material(
            color: pinned || unread > 0
                ? CustomerTheme.primarySurface
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: CustomerTheme.borderColor),
            ),
            child: InkWell(
              onTap: _busy ? null : widget.onOpen,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: CustomerTheme.primarySurface,
                      child: Icon(
                        Icons.person_outline,
                        color: CustomerTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.row['peer_name']?.toString() ??
                                tr('Conversation'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.row['preview']?.toString() ??
                                tr('Start a conversation'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: CustomerTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pinned)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.push_pin, size: 16),
                      ),
                    if (unread > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Badge(
                          label: Text(tr(unread > 99 ? '99+' : '$unread')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
