import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/customer_theme.dart';
import '../../models/booking_model.dart';
import '../../services/customer_address_service.dart';
import '../../services/customer_transaction_service.dart';
import '../home/add_address_map_screen.dart';
import 'customer_booking_detail_screen.dart';

class CustomerBookingFormScreen extends StatefulWidget {
  final Map<String, dynamic> serviceData;
  final Map<String, dynamic> providerData;
  final CustomerTransactionService? transactions;
  final CustomerAddressService? addresses;
  const CustomerBookingFormScreen({
    super.key,
    required this.serviceData,
    required this.providerData,
    this.transactions,
    this.addresses,
  });
  @override
  State<CustomerBookingFormScreen> createState() =>
      _CustomerBookingFormScreenState();
}

class _CustomerBookingFormScreenState extends State<CustomerBookingFormScreen> {
  late final CustomerTransactionService _transactions =
      widget.transactions ?? CustomerTransactionService();
  late final CustomerAddressService _addressService =
      widget.addresses ?? CustomerAddressService();
  final _instructions = TextEditingController();
  DateTime _date = DateTime.now().toUtc().add(
    const Duration(hours: 8, days: 1),
  );
  List<BookingSlot> _slots = [];
  List<Map<String, dynamic>> _addresses = [];
  String? _addressId;
  String? _time;
  String? _slotsError;
  String? _addressError;
  bool _loadingSlots = true;
  bool _loadingAddresses = true;
  bool _saving = false;
  int _slotRequest = 0;
  String _requestId = CustomerTransactionService.newRequestId();
  @override
  void initState() {
    super.initState();
    _loadSlots();
    _loadAddresses();
  }

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _loadSlots() async {
    final request = ++_slotRequest;
    setState(() {
      _loadingSlots = true;
      _slotsError = null;
      _time = null;
    });
    try {
      final slots = await _transactions.getAvailableTimeSlots(
        serviceId: widget.serviceData['service_id'] as String,
        date: _date,
      );
      if (mounted && request == _slotRequest) setState(() => _slots = slots);
    } catch (error) {
      if (mounted && request == _slotRequest)
        setState(() => _slotsError = bookingError(error));
    } finally {
      if (mounted && request == _slotRequest)
        setState(() => _loadingSlots = false);
    }
  }

  Future<void> _loadAddresses() async {
    setState(() {
      _loadingAddresses = true;
      _addressError = null;
    });
    try {
      final addresses = await _addressService.getSavedAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        if (!addresses.any((row) => row['address_id'] == _addressId)) {
          _addressId = addresses.isEmpty
              ? null
              : addresses.first['address_id'] as String;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _addressError = bookingError(error));
    } finally {
      if (mounted) setState(() => _loadingAddresses = false);
    }
  }

  Future<void> _chooseDate() async {
    final malaysia = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime(malaysia.year, malaysia.month, malaysia.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _date = date;
      _requestId = CustomerTransactionService.newRequestId();
    });
    await _loadSlots();
  }

  Future<void> _book() async {
    if (_saving || _time == null || _addressId == null) return;
    setState(() => _saving = true);
    try {
      final booking = await _transactions.createPendingBooking(
        serviceId: widget.serviceData['service_id'] as String,
        addressId: _addressId!,
        date: _date,
        scheduledTime: _time!,
        requestId: _requestId,
        specialInstructions: _instructions.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CustomerBookingDetailScreen(
            bookingId: booking.id,
            transactions: _transactions,
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(bookingError(error))));
      // Keep the request token: a lost response must not create a second booking.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price =
        double.tryParse((widget.serviceData['quoted_amount'] ?? widget.serviceData['base_price']).toString()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Book service')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.serviceData['service_name']?.toString() ?? 'Service',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(widget.providerData['business_name']?.toString() ?? ''),
            const SizedBox(height: 12),
            Text(
              'RM ${price.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 22,
                color: CustomerTheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'The current price and appointment will be checked when you book.',
            ),
            const SizedBox(height: 24),
            const Text(
              'Service address',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_loadingAddresses)
              const LinearProgressIndicator()
            else if (_addressError != null) ...[
              Text(_addressError!),
              TextButton(
                onPressed: _loadAddresses,
                child: const Text('Retry addresses'),
              ),
            ] else if (_addresses.isEmpty)
              const Text('Add a saved address before booking.')
            else
              DropdownButtonFormField<String>(
                initialValue: _addressId,
                isExpanded: true,
                items: _addresses
                    .map(
                      (address) => DropdownMenuItem(
                        value: address['address_id'] as String,
                        child: Text(
                          '${address['label'] ?? 'Address'}: ${address['address_line']}, ${address['city']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _addressId = value;
                  _requestId = CustomerTransactionService.newRequestId();
                }),
              ),
            TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AddAddressMapScreen(),
                  ),
                );
                if (mounted) await _loadAddresses();
              },
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add address'),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Appointment date'),
              subtitle: Text(
                '${DateFormat('EEE, d MMM yyyy').format(_date)} · Malaysia time',
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: _chooseDate,
            ),
            const SizedBox(height: 12),
            const Text(
              'Available times',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_loadingSlots)
              const LinearProgressIndicator()
            else if (_slotsError != null) ...[
              Text(_slotsError!),
              TextButton(
                onPressed: _loadSlots,
                child: const Text('Retry availability'),
              ),
            ] else if (_slots.isEmpty)
              const Text(
                'No appointments available on this date. Choose another date.',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _slots
                    .map(
                      (slot) => ChoiceChip(
                        label: Text(slot.label),
                        selected: _time == slot.time,
                        onSelected: (_) => setState(() {
                          _time = slot.time;
                          _requestId =
                              CustomerTransactionService.newRequestId();
                        }),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: _instructions,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Instructions (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) =>
                  _requestId = CustomerTransactionService.newRequestId(),
            ),
            const SizedBox(height: 12),
            const Text(
              'You can track your booking and payment status in My bookings.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed:
                _saving ||
                    _loadingSlots ||
                    _loadingAddresses ||
                    _time == null ||
                    _addressId == null ||
                    _slotsError != null ||
                    _addressError != null
                ? null
                : _book,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create booking'),
            ),
          ),
        ),
      ),
    );
  }
}
