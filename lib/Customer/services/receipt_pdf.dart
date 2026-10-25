import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/booking_model.dart';

class PaymentReceipt {
  final CustomerBooking booking;
  final Map<String, dynamic> payment;
  PaymentReceipt(Map<String, dynamic> data)
    : booking = CustomerBooking.fromJson(
        Map<String, dynamic>.from(data['booking'] as Map),
      ),
      payment = Map<String, dynamic>.from(data['payment'] as Map) {
    if (!['Success', 'Refunded'].contains(payment['payment_status']) ||
        double.tryParse(payment['payment_amount'].toString()) == null) {
      throw const FormatException(
        'A verified payment is required for a receipt.',
      );
    }
  }
  String get reference =>
      payment['fpx_transaction_ref']?.toString() ??
      payment['payment_id']?.toString() ??
      'Unavailable';
  String get number => payment['payment_id']?.toString() ?? booking.id;
  String get amount =>
      'RM ${double.parse(payment['payment_amount'].toString()).toStringAsFixed(2)}';
  bool get refunded => payment['payment_status'] == 'Refunded';
  String get status => refunded ? 'REFUNDED' : 'PAID';
  String get method =>
      switch (payment['gateway_method'] ?? payment['payment_method']) {
        'card' || 'CreditCard' => 'Debit / credit card',
        'grabpay' => 'GrabPay',
        'fpx' || 'FPX' => 'FPX online banking',
        'E-Wallet' => 'E-wallet',
        _ => 'Unavailable',
      };
  String get paidAt {
    final time = DateTime.tryParse(
      payment['payment_timestamp']?.toString() ?? '',
    );
    return time == null
        ? tr('Unavailable')
        : tr("{0} MYT", [
            DateFormat.yMMMd().add_jm().format(
              time.toUtc().add(const Duration(hours: 8)),
            ),
          ]);
  }

  String get filename =>
      'Home-Serve-Receipt-${booking.id.replaceAll(RegExp('[^a-zA-Z0-9-]'), '')}.pdf';
  List<(String, String)> get details => [
    ('Receipt number', number),
    ('Booking reference', booking.id),
    ('Payment reference', reference),
    ('Payment recorded', paidAt),
    ('Payment method', tr(method)),
    ('Provider', booking.providerName),
    ('Appointment (Malaysia time)', booking.appointmentLabel),
    ('Service address', booking.address),
    ('Booking status', tr(booking.displayStatus)),
  ];
}

Future<Uint8List> buildReceiptPdf(PaymentReceipt receipt) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-bold.ttf'),
  );
  final chinese = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto-sans-sc-regular.ttf'),
  );
  final doc = pw.Document(
    title: tr("Local Life Service Assistant payment receipt {0}", [receipt.number]),
    author: 'Local Life Service Assistant',
  );
  const orange = PdfColor.fromInt(0xFFFF6B00);
  const green = PdfColor.fromInt(0xFF157347);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [chinese],
      ),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: PdfColors.grey300),
          pw.Text(
            tr('SANDBOX TEST RECEIPT - No real money transferred.'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            tr("Local Life Service Assistant  |  Page {0} of {1}", [
              context.pageNumber,
              context.pagesCount,
            ]),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
      build: (_) => [
        pw.Text(
          tr('Local Life Service Assistant'),
          style: pw.TextStyle(
            fontSize: 26,
            fontWeight: pw.FontWeight.bold,
            color: orange,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          tr('PAYMENT RECEIPT'),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 24),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                tr(receipt.status),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: receipt.refunded ? PdfColors.grey700 : green,
                ),
              ),
              pw.Text(
                receipt.amount,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          tr('SERVICE'),
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          receipt.booking.serviceName,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 18),
        for (final row in receipt.details)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 9),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 145,
                  child: pw.Text(
                    tr(row.$1),
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    row.$2,
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 10),
        pw.Text(
          tr(
            receipt.refunded
                ? 'This payment is recorded as refunded. The original payment details are retained for your records.'
                : 'This receipt reflects the payment confirmed by the server. Keep the payment reference when contacting support.',
          ),
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          tr(
            'This is a sandbox demonstration receipt, not a tax invoice or evidence of a real bank transfer.',
          ),
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  return doc.save();
}
