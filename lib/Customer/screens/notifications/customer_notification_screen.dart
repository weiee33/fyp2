import '../../widgets/customer_refresh.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../shared/chat/chat_inbox_screen.dart';
import '../../../shared/chat/chat_screen.dart';
import '../../widgets/customer_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/customer_theme.dart';
import '../../services/customer_notification_service.dart';
import '../../services/customer_live_updates.dart';
import '../booking/customer_booking_detail_screen.dart';

class CustomerNotificationScreen extends StatefulWidget {
  final CustomerNotificationService? service;
  const CustomerNotificationScreen({super.key, this.service});

  @override
  State<CustomerNotificationScreen> createState() =>
      _CustomerNotificationScreenState();
}

class _CustomerNotificationScreenState
    extends State<CustomerNotificationScreen> {
  late final CustomerNotificationService _notificationService;

  List<Map<String, dynamic>> _allNotifications = [];
  bool _isLoading = true;
  final Set<String> _busy = {};
  int _loadVersion = 0;
  String? _loadError;
  CustomerLiveUpdates? _updates;

  // Filter types matching FYP 1 specification[cite: 455]
  final List<String> _filters = [
    'All',
    'Booking',
    'Payment',
    'System',
    'Message',
  ];
  String _activeFilter = 'All';

  @override
  void initState() {
    super.initState();
    _notificationService = widget.service ?? CustomerNotificationService();
    _fetchNotifications();
    if (widget.service == null)
      _updates = CustomerLiveUpdates(_fetchNotifications);
  }

  @override
  void dispose() {
    _updates?.dispose();
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
    final version = ++_loadVersion;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await _notificationService.getNotifications();
      if (mounted && version == _loadVersion) {
        setState(() {
          _allNotifications = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      if (mounted)
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load notifications. Pull down to retry.';
        });
      if (mounted)
        CustomerDialogs.show(
          context,
          title: 'Unable to load',
          message: 'Could not load notifications. Please retry.',
        );
    }
  }

  Future<void> _manage(Map<String, dynamic> row, {required bool delete}) async {
    final id = row['notification_id'] as String;
    if (!_busy.add(id)) return;
    try {
      if (delete &&
          !await CustomerDialogs.confirm(
            context,
            title: 'Delete notification?',
            message:
                'Remove this notification from your list? Your booking is unchanged.',
          ))
        return;
      if (delete) {
        await _notificationService.deleteNotification(id);
      } else {
        await _notificationService.setPinned(id, row['is_pinned'] != true);
      }
      if (!mounted) return;
      await _fetchNotifications();
      if (!mounted) return;
      await CustomerDialogs.show(
        context,
        message: delete
            ? 'Notification deleted.'
            : row['is_pinned'] == true
            ? 'Notification unpinned.'
            : 'Notification pinned.',
      );
    } catch (e) {
      if (mounted) await CustomerDialogs.error(context, e);
    } finally {
      _busy.remove(id);
    }
  }

  void _showError(String message) {
    if (mounted) CustomerDialogs.show(context, message: message);
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notification) async {
    final bool isRead = notification['is_read'] ?? false;
    final String id = notification['notification_id'];
    final String? bookingId = notification['booking_id'];

    if (!isRead) {
      try {
        await _notificationService.markAsRead(id);
        if (!mounted) return;
        setState(() => notification['is_read'] = true);
      } catch (_) {
        _showError('Could not mark this notification as read.');
        return;
      }
    }

    if (!mounted) return;

    // Deep-link navigation based on context[cite: 454, 455]
    final link = notification['deep_link']?.toString() ?? '';
    if (RegExp(r'^chat/[0-9a-fA-F-]{36}$').hasMatch(link)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConversationScreen(conversationId: link.substring(5)),
        ),
      );
    } else if (bookingId != null && bookingId.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerBookingDetailScreen(bookingId: bookingId),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(notification['title']?.toString() ?? 'Notification'),
          content: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Text(notification['message']?.toString() ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply client-side filtering[cite: 455]
    final filteredNotifications = _activeFilter == 'All'
        ? _allNotifications
        : _allNotifications
              .where(
                (n) => _activeFilter == 'Booking'
                    ? [
                        'New Booking',
                        'Booking Update',
                        'Cancellation',
                      ].contains(n['notification_type'])
                    : n['notification_type'] == _activeFilter,
              )
              .toList();

    return Theme(
      data: CustomerTheme.lightTheme,
      child: Scaffold(
        backgroundColor: CustomerTheme.background,
        body: CustomerRefresh(
          color: CustomerTheme.primary,
          onRefresh: _fetchNotifications,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // Mobile-native Elastic AppBar
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 2,
                title: const Text(
                  'Notifications',
                  style: TextStyle(color: CustomerTheme.textPrimary),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Chats',
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChatInboxScreen(),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildFilterCarousel(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // Notification List
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: CustomerTheme.primary,
                    ),
                  ),
                )
              else if (_loadError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_loadError!),
                        TextButton(
                          onPressed: _fetchNotifications,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_isLoading &&
                  _loadError == null &&
                  filteredNotifications.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_rounded,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No ${_activeFilter == 'All' ? '' : _activeFilter} notifications yet.',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!_isLoading && filteredNotifications.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final notification = filteredNotifications[index];
                      return _buildNotificationCard(notification);
                    }, childCount: filteredNotifications.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Animated Horizontal Filter Carousel[cite: 455]
  Widget _buildFilterCarousel() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _activeFilter == filter;

          return ChoiceChip(
            label: Text(filter),
            selected: isSelected,
            onSelected: (selected) {
              HapticFeedback.selectionClick();
              setState(() => _activeFilter = filter);
            },
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : CustomerTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
            selectedColor: CustomerTheme.primary,
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected
                    ? CustomerTheme.primary
                    : CustomerTheme.borderColor,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Swipe-to-Dismiss Mobile Notification Card
  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final String id = notification['notification_id'];
    final bool isRead = notification['is_read'] ?? false;
    final String title = notification['title'] ?? 'Alert';
    final String message = notification['message'] ?? '';
    final String type = notification['notification_type'] ?? 'System';
    final DateTime? createdAt = DateTime.tryParse(
      notification['created_at']?.toString() ?? '',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: .5,
          children: [
            SlidableAction(
              onPressed: (_) => _manage(notification, delete: false),
              backgroundColor: CustomerTheme.primary,
              foregroundColor: Colors.white,
              icon: notification['is_pinned'] == true
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
              label: notification['is_pinned'] == true ? 'Unpin' : 'Pin',
            ),
            SlidableAction(
              onPressed: (_) => _manage(notification, delete: true),
              backgroundColor: CustomerTheme.danger,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'Delete',
            ),
          ],
        ),
        child: InkWell(
          onTap: () => _handleNotificationTap(notification),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isRead
                  ? Colors.white
                  : CustomerTheme.primarySurface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isRead
                    ? CustomerTheme.borderColor
                    : CustomerTheme.primaryLight.withOpacity(0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type Icon
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _getIconColor(type).withOpacity(0.15),
                  child: Icon(
                    _getIcon(type),
                    color: _getIconColor(type),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isRead
                                    ? FontWeight.w600
                                    : FontWeight.bold,
                                color: CustomerTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            createdAt == null
                                ? ''
                                : timeago.format(createdAt, locale: 'en_short'),
                            style: TextStyle(
                              fontSize: 12,
                              color: isRead
                                  ? CustomerTheme.textSecondary
                                  : CustomerTheme.primary,
                              fontWeight: isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 13,
                          color: isRead
                              ? CustomerTheme.textSecondary
                              : Colors.black87,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                PopupMenuButton<String>(
                  tooltip: 'Notification actions',
                  onSelected: (action) =>
                      _manage(notification, delete: action == 'delete'),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(
                        notification['is_pinned'] == true ? 'Unpin' : 'Pin',
                      ),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  icon: Icon(
                    notification['is_pinned'] == true
                        ? Icons.push_pin
                        : Icons.more_vert,
                    size: 18,
                  ),
                ),
                // Unread Indicator
                if (!isRead) ...[
                  const SizedBox(width: 12),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: CustomerTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type.toLowerCase()) {
      case 'booking':
        return Icons.handyman_rounded;
      case 'payment':
        return Icons.account_balance_wallet_rounded;
      case 'promotion':
        return Icons.local_offer_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _getIconColor(String type) {
    switch (type.toLowerCase()) {
      case 'booking':
        return const Color(0xFF2563EB); // Blue
      case 'payment':
        return const Color(0xFF10B981); // Green
      case 'promotion':
        return const Color(0xFFF59E0B); // Amber
      default:
        return Colors.grey.shade600;
    }
  }
}
