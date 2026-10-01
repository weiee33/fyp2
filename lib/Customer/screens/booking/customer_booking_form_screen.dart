import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/customer_theme.dart';
import '../../services/customer_transaction_service.dart';
import '../payment/customer_checkout_screen.dart';

class CustomerBookingFormScreen extends StatefulWidget {
  final Map<String, dynamic> serviceData;
  final Map<String, dynamic> providerData;

  const CustomerBookingFormScreen({
    super.key,
    required this.serviceData,
    required this.providerData,
  });

  @override
  State<CustomerBookingFormScreen> createState() => _CustomerBookingFormScreenState();
}

class _CustomerBookingFormScreenState extends State<CustomerBookingFormScreen> {
  final CustomerTransactionService _txService = CustomerTransactionService();
  final TextEditingController _instructionsController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedTime;
  String _urgency = 'Medium';
  bool _isProcessing = false;

  final List<DateTime> _availableDates = List.generate(14, (i) => DateTime.now().add(Duration(days: i + 1)));

  void _proceedToCheckout() async {
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot'), backgroundColor: CustomerTheme.danger),
      );
      return;
    }

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      // Create pending booking in database[cite: 447]
      final booking = await _txService.createPendingBooking(
        providerId: widget.providerData['provider_id'],
        serviceId: widget.serviceData['service_id'],
        date: _selectedDate,
        timeString: _selectedTime!,
        totalAmount: (widget.serviceData['base_price'] as num).toDouble(),
        specialInstructions: _instructionsController.text.trim(),
        urgency: _urgency,
      );

      if (!mounted) return;

      // Navigate to Checkout via native swipe route[cite: 447]
      Navigator.pushReplacement(
        context,
        CupertinoPageRoute(
          builder: (_) => CustomerCheckoutScreen(
            bookingData: booking,
            providerData: widget.providerData,
            serviceData: widget.serviceData,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize booking: $e'), backgroundColor: CustomerTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeSlots = _txService.getAvailableTimeSlots(_selectedDate);
    final price = (widget.serviceData['base_price'] as num).toDouble();

    return Scaffold(
      backgroundColor: CustomerTheme.background,
      appBar: AppBar(title: const Text('Book Service'), elevation: 0),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                // Service Summary Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: CustomerTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: CustomerTheme.primarySurface,
                        child: const Icon(Icons.handyman_rounded, color: CustomerTheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.serviceData['service_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(widget.providerData['business_name'], style: const TextStyle(color: CustomerTheme.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                      Text('RM ${price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: CustomerTheme.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Horizontal Date Selector
                const Text('Select Date', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 85,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _availableDates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final date = _availableDates[i];
                      final isSelected = _selectedDate.day == date.day && _selectedDate.month == date.month;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedDate = date;
                            _selectedTime = null; // reset time on new date
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 65,
                          decoration: BoxDecoration(
                            color: isSelected ? CustomerTheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? CustomerTheme.primary : CustomerTheme.borderColor),
                            boxShadow: isSelected ? [BoxShadow(color: CustomerTheme.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(DateFormat('MMM').format(date).toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white70 : CustomerTheme.textSecondary)),
                              const SizedBox(height: 4),
                              Text(DateFormat('dd').format(date), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : CustomerTheme.textPrimary)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Time Slots Grid
                const Text('Available Time', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: timeSlots.map((time) {
                    final isSelected = _selectedTime == time;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedTime = time);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? CustomerTheme.primarySurface : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? CustomerTheme.primary : CustomerTheme.borderColor, width: isSelected ? 2 : 1),
                        ),
                        child: Text(
                          time,
                          style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? CustomerTheme.primary : CustomerTheme.textPrimary),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),

                // Special Instructions
                const Text('Special Instructions (Optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _instructionsController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Please bring extra long ladder...',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: CustomerTheme.borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: CustomerTheme.borderColor)),
                  ),
                ),
              ],
            ),
          ),

          // Sticky Bottom Bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
            ),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _proceedToCheckout,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isProcessing
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Proceed to Checkout', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}