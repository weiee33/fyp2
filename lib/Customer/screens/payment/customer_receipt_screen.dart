import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/receipt_pdf.dart';
import '../../services/receipt_save_web.dart'
    if (dart.library.io) '../../services/receipt_save_io.dart';
import '../../services/customer_transaction_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/customer_theme.dart';
import '../../widgets/customer_dialogs.dart';

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
      final saved = await (widget.savePdf ?? saveReceiptFile)(
        current.filename,
        bytes,
      );
      if (!mounted || !saved) return;
      await showCustomerDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            tr(kIsWeb ? 'Receipt download started' : 'Receipt saved'),
            style: const TextStyle(color: CustomerTheme.primary),
          ),
          content: Text(
            tr(
              kIsWeb
                  ? 'Your PDF receipt has been sent to your browser downloads.'
                  : 'Your PDF receipt has been saved to your selected location.',
            ),
          ),
          actions: [
            FilledButton(
              style: CustomerTheme.actionStyle(),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('OK')),
            ),
          ],
        ),
      );
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
    return CustomerScaffold(
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
                      Expanded(
                        child: Text(
                          tr('Local Life Service Assistant'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6B00),
                          ),
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
                ],
              ),
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
                child: FilledButton(
                  onPressed: _saving ? null : _download,
                  child: Padding(
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
