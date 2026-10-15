import 'package:fyp2/shared/localization/app_language.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/receipt_pdf.dart';
import '../../services/receipt_save_web.dart'
    if (dart.library.io) '../../services/receipt_save_io.dart';
import '../../services/customer_transaction_service.dart';
import '../../widgets/booking_section.dart';

class CustomerReceiptScreen extends StatefulWidget {
  final String bookingId;
  final CustomerTransactionService? transactions;
  final Future<bool> Function(String filename, Uint8List bytes)? savePdf;
  const CustomerReceiptScreen({
    super.key,
    required this.bookingId,
    this.transactions,
    this.savePdf,
  });
  @override
  State<CustomerReceiptScreen> createState() => _CustomerReceiptScreenState();
}

class _CustomerReceiptScreenState extends State<CustomerReceiptScreen> {
  late final _transactions =
      widget.transactions ?? CustomerTransactionService();
  PaymentReceipt? _receipt;
  String? _error, _saveError;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final receipt = PaymentReceipt(
        await _transactions.getReceipt(widget.bookingId),
      );
      if (mounted) setState(() => _receipt = receipt);
    } catch (error) {
      if (mounted) setState(() => _error = bookingError(error));
    }
  }

  Future<void> _download() async {
    if (_saving || _receipt == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      // Re-fetch the authorised record so a refund/status change is reflected in the export.
      final current = PaymentReceipt(
        await _transactions.getReceipt(widget.bookingId),
      );
      final bytes = await buildReceiptPdf(current);
      if (!mounted) return;
      setState(() => _receipt = current);
      if (widget.savePdf != null) {
        await widget.savePdf!(current.filename, bytes);
      } else {
        await saveReceiptFile(current.filename, bytes);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = 'Could not save your receipt. Please try again.',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(_saveError!))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final receipt = _receipt;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Payment Receipt'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text(tr(_error!)),
            TextButton(onPressed: _load, child: Text(tr('Try again'))),
          ] else if (receipt == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E5EA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        color: Color(0xFFFF6B00),
                        size: 28,
                      ),
                      SizedBox(width: 10),
                      Text(
                        tr('HOME SERVE'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B00),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tr('PAYMENT RECEIPT'),
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.3,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    receipt.amount,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        receipt.refunded ? Icons.undo : Icons.check_circle,
                        color: receipt.refunded
                            ? Colors.blueGrey
                            : const Color(0xFF157347),
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tr(receipt.status),
                        style: TextStyle(
                          color: receipt.refunded
                              ? Colors.blueGrey
                              : const Color(0xFF157347),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Text(
                    receipt.booking.serviceName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(receipt.booking.providerName),
                  const Divider(height: 32),
                  for (final row in receipt.details.where(
                    (row) => row.$1 != 'Provider',
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(row.$1),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 5),
                          SelectableText(
                            row.$2,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Text(
                    tr('SANDBOX TEST RECEIPT'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      'No real money transferred. This demonstration receipt is not a tax invoice.',
                    ),
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BookingSection(
              title: tr('Keep your payment record'),
              icon: Icons.verified_user_outlined,
              children: [
                Text(
                  tr(
                    'Download a PDF copy for your records. Include the payment reference when requesting booking support.',
                  ),
                ),
              ],
            ),
          ],
          if (_saveError != null)
            Text(tr(_saveError!), style: const TextStyle(color: Colors.red)),
        ],
      ),
      bottomNavigationBar: receipt == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _download,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      tr(_saving ? 'Preparing PDF…' : 'Download receipt (PDF)'),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
