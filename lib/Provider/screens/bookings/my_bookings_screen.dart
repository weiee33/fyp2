import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import 'booking_detail_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final _service = BookingService();

  final tabs = ['New', 'Confirmed', 'In-Progress', 'Completed'];
  final statusMap = {
    'New': 'Pending',
    'Confirmed': 'Confirmed',
    'In-Progress': 'In-Progress',
    'Completed': 'Completed',
  };

  int _tab = 0;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  // 🎨 Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final items =
      await _service.getMyBookings(status: statusMap[tabs[_tab]]);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load bookings: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ---- Status Filter Chips ----
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(tabs.length, (i) {
                    final selected = _tab == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _tab = i);
                          _load();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? _primaryOrange
                                : _lightOrange,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? _primaryOrange
                                  : _borderOrange,
                            ),
                          ),
                          child: Text(
                            tabs[i],
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : _primaryOrange,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const Divider(height: 1),

            // ---- List ----
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                onRefresh: _load,
                color: _primaryOrange,
                child: _items.isEmpty
                    ? _buildEmpty()
                    : ListView(
                  padding: const EdgeInsets.all(16),
                  children:
                  _items.map((b) => _bookingCard(b)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: const [
        SizedBox(height: 100),
        Icon(Icons.event_busy_outlined, size: 56, color: Colors.grey),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No bookings',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: 4),
        Center(
          child: Text(
            'New booking requests will appear here',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    // ---- Safe field extraction with fallbacks ----
    final rawId = b['booking_id']?.toString() ?? '';
    final shortId =
    rawId.isEmpty ? 'N/A' : (rawId.length >= 8 ? rawId.substring(0, 8) : rawId);

    final cust = b['customer_profiles']?['users']?['full_name']?.toString() ??
        'Customer';
    final svc = b['services']?['service_name']?.toString() ?? 'Service';

    final amountRaw = b['total_amount'];
    final amountText = amountRaw == null
        ? '—'
        : (amountRaw is num
        ? amountRaw.toStringAsFixed(0)
        : amountRaw.toString());

    final status = b['booking_status']?.toString() ?? 'Pending';
    final date = b['booking_date']?.toString() ?? 'Date TBA';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderOrange),
      ),
      child: InkWell(
        onTap: () {
          if (rawId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Booking ID missing')),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BookingDetailScreen(bookingId: rawId)),
          ).then((_) => _load());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Header: ID + Amount ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _lightOrange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          color: _primaryOrange,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '#$shortId',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    amountRaw == null ? '—' : 'RM$amountText',
                    style: const TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ---- Customer ----
              _infoRow(Icons.person_outline, cust),
              const SizedBox(height: 4),

              // ---- Service ----
              _infoRow(Icons.build_outlined, svc),
              const SizedBox(height: 4),

              // ---- Date ----
              _infoRow(Icons.calendar_today_outlined, date),
              const SizedBox(height: 12),

              // ---- Status + View detail ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statusBadge(status),
                  const Text(
                    'View detail →',
                    style: TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4B5563),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'confirmed':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1E40AF);
        icon = Icons.check_circle_outline;
        break;
      case 'in-progress':
        bg = _lightOrange;
        fg = _primaryOrange;
        icon = Icons.timelapse;
        break;
      case 'completed':
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF065F46);
        icon = Icons.done_all;
        break;
      case 'cancelled':
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFF991B1B);
        icon = Icons.cancel_outlined;
        break;
      default:
      // Pending / New
        bg = _lightOrange;
        fg = _primaryOrange;
        icon = Icons.pending_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}