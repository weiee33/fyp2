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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items =
        await _service.getMyBookings(status: statusMap[tabs[_tab]]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: tabs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 8),
                child: ChoiceChip(
                  label: Text(tabs[i]),
                  selected: _tab == i,
                  onSelected: (_) {
                    setState(() => _tab = i);
                    _load();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 200),
                        Center(child: Text('No bookings')),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: _items.map((b) {
                        final cust = b['customer_profiles']?['users']?['full_name'] ?? 'Customer';
                        final svc = b['services']?['service_name'] ?? 'Service';
                        final amount = b['total_amount'] ?? 0;
                        final status = b['booking_status'] ?? 'Pending';
                        final date = b['booking_date'] ?? '';

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('#${b['booking_id'].toString().substring(0, 8)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text('RM$amount',
                                        style: const TextStyle(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('$cust · $svc'),
                                Text('$date · Status: $status',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => BookingDetailScreen(
                                              bookingId: b['booking_id'])),
                                    ).then((_) => _load()),
                                    child: const Text('View detail →'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
    );
  }
}