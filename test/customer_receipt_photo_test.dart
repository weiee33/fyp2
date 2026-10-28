import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fyp2/Customer/services/receipt_pdf.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/Customer/screens/payment/customer_receipt_screen.dart';
import 'package:fyp2/Customer/screens/payment/customer_checkout_screen.dart';
import 'package:fyp2/Customer/screens/booking/customer_bookings_screen.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_detail_screen.dart';
import 'package:fyp2/Customer/widgets/booking_status.dart';
import 'package:fyp2/shared/chat/chat_service.dart';
import 'package:fyp2/shared/chat/chat_screen.dart';
import 'customer_workflow_test.dart' as fixtures;
import 'customer_accounts_chat_test.dart' as capture;

final photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=',
);
Map<String, dynamic> receiptData({bool refunded = false}) {
  final booking = fixtures.booking(status: 'Confirmed', paid: true);
  final payment = Map<String, dynamic>.from(booking['payment'] as Map)
    ..addAll({
      'payment_id': 'receipt-123',
      'payment_timestamp': '2026-10-11T08:30:00Z',
      'payment_status': refunded ? 'Refunded' : 'Success',
    });
  booking['payment'] = payment;
  return {'booking': booking, 'payment': payment};
}

class PhotoChat extends ChatService {
  PhotoChat() : super(rpc: (_, _) async => null);
  int sends = 0;
  final requests = <String>[];
  final messages = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> history(String id, {int? before}) async => {
    'messages': messages,
    'peer_name': 'Local Provider',
    'can_send': true,
  };
  @override
  Future<void> manage(String id, String action, {int? readThrough}) async {}
  @override
  Future<Map<String, dynamic>> sendPhoto(
    String id,
    Uint8List bytes,
    String requestId,
  ) async {
    requests.add(requestId);
    if (sends++ == 0) throw Exception('connection interrupted');
    final message = {
      'message_id': 1,
      'request_id': requestId,
      'body': 'Photo',
      'attachment_path': 'private/photo.png',
      'is_mine': true,
      'created_at': '2026-10-11T08:30:00Z',
    };
    messages.add(message);
    return message;
  }

  @override
  Future<Uint8List> photo(String path) async => Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=',
    ),
  );
}

void main() {
  setUpAll(() async {
    // Geometry assertions use the app font on CI as well as local captures.
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))).load();
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      for (final entry in {
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            File(
              '$root/${entry.value}',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await loader.load();
      }
    }
  });
  test('photo validation rejects nonimages and oversized files', () {
    expect(ChatService.photoMime(photo), 'image/png');
    expect(
      () => ChatService.photoMime(
        Uint8List.fromList(utf8.encode('<script>bad</script>')),
      ),
      throwsFormatException,
    );
    expect(
      () => ChatService.photoMime(Uint8List(5 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
  test('receipt refuses unpaid records', () {
    final data = receiptData();
    (data['payment'] as Map)['payment_status'] = 'Failed';
    expect(() => PaymentReceipt(data), throwsFormatException);
  });
  testWidgets('receipt export refreshes authoritative data and generates PDF', (
    t,
  ) async {
    capture.pixel(t);
    var refunded = false;
    Uint8List? exported;
    await t.pumpWidget(
      capture.app(
        CustomerReceiptScreen(
          bookingId: 'booking',
          transactions: CustomerTransactionService(
            rpc: (_, _) async => receiptData(refunded: refunded),
          ),
          savePdf: (name, bytes) async {
            exported = bytes;
            expect(name, endsWith('.pdf'));
            return true;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('PAID'), findsOneWidget);
    await capture.proof(t, 'receipt-redesign');
    refunded = true;
    await t.runAsync(() async {
      await t.tap(find.text('Download receipt (PDF)'));
    });
    // PDF asset/file work uses real async while Flutter state uses the test zone.
    for (var i = 0; i < 150 && exported == null; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(exported, isNotNull);
    expect(utf8.decode(exported!.take(5).toList()), '%PDF-');
    expect(find.text('REFUNDED'), findsOneWidget);
    expect(find.text('Receipt saved'), findsOneWidget);
    expect(
      find.text('Your PDF receipt has been saved to your selected location.'),
      findsOneWidget,
    );
    final ok = find.widgetWithText(FilledButton, 'OK');
    final button = t.widget<FilledButton>(ok);
    expect(button.style!.shape!.resolve({}), CustomerTheme.actionShape);
    await capture.proof(t, 'receipt-save-confirmation');
    await t.tap(ok);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await t.runAsync(() async {
        await File(
          '.tools/customer-ui/sample-receipt.pdf',
        ).writeAsBytes(exported!);
      });
    }
    expect(t.takeException(), isNull);
  });
  for (final fails in [false, true]) {
    testWidgets(
      fails
          ? 'receipt save failure does not show success'
          : 'cancelled receipt save does not show success',
      (t) async {
        capture.pixel(t);
        var called = false;
        await t.pumpWidget(
          capture.app(
            CustomerReceiptScreen(
              bookingId: 'booking',
              transactions: CustomerTransactionService(
                rpc: (_, _) async => receiptData(),
              ),
              savePdf: (_, _) async {
                called = true;
                if (fails) throw StateError('Save failed');
                return false;
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(find.text('Download receipt (PDF)'));
        });
        for (var i = 0; i < 150 && !called; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await t.pump();
        }
        await t.pumpAndSettle();
        expect(called, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Receipt saved'), findsNothing);
        expect(
          find.text('Could not save your receipt. Please try again.'),
          fails ? findsWidgets : findsNothing,
        );
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Download receipt (PDF)'),
              )
              .onPressed,
          isNotNull,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'bookings distinguish paid expired and refunded at narrow width',
    (t) async {
      capture.pixel(t);
      t.view.physicalSize = const Size(360, 808);
      final paid = fixtures.booking(status: 'Confirmed', paid: true);
      final expired = fixtures.booking(status: 'Confirmed')
        ..['reservation_expired'] = true;
      final refunded = Map<String, dynamic>.from(
        receiptData(refunded: true)['booking'],
      );
      await t.pumpWidget(
        capture.app(
          CustomerBookingsScreen(
            transactions: CustomerTransactionService(
              rpc: (_, _) async => [paid, expired, refunded],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Expired · Not paid'), findsOneWidget);
      expect(find.text('Refunded'), findsOneWidget);
      await capture.proof(t, 'bookings-status');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('paid details shows verified payment and process', (t) async {
    capture.pixel(t);
    await t.pumpWidget(
      capture.app(
        CustomerBookingDetailScreen(
          bookingId: 'booking',
          transactions: CustomerTransactionService(
            rpc: (_, _) async =>
                fixtures.booking(status: 'Confirmed', paid: true),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await capture.proof(t, 'booking-paid-details');
    expect(find.text('Payment received'), findsWidgets);
    final status = t.getRect(find.byKey(const ValueKey('booking-status')));
    final paid = t.getRect(find.byType(BookingPaymentStatus).first);
    expect(paid.height, status.height);
    expect(paid.center.dy, status.center.dy);
    await t.scrollUntilVisible(find.text('View Receipt'), 300);
    await t.pumpAndSettle();
    final receiptButton = t.getRect(
      find.widgetWithText(OutlinedButton, 'View Receipt'),
    );
    final paymentBadge = t.getRect(find.byType(BookingPaymentStatus).last);
    expect(paymentBadge.height, receiptButton.height);
    expect(paymentBadge.center.dy, closeTo(receiptButton.center.dy, 1));
    await capture.proof(t, 'booking-paid-summary');
    expect(t.takeException(), isNull);
  });
  testWidgets('refunded checkout does not announce a new successful payment', (
    t,
  ) async {
    capture.pixel(t);
    await t.pumpWidget(
      capture.app(
        CustomerCheckoutScreen(
          bookingId: 'booking',
          transactions: CustomerTransactionService(
            rpc: (_, _) async => receiptData(refunded: true)['booking'],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Payment refunded'), findsWidgets);
    expect(find.text('Payment confirmed'), findsNothing);
    expect(find.text('Refund recorded'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('countdown reaches expiry and is disposed', (t) async {
    final deadline = DateTime.now().add(const Duration(milliseconds: 200));
    await t.pumpWidget(capture.app(PaymentCountdown(deadline: deadline)));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Payment window ended'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'photo source choice preview and failed send retain retry identity',
    (t) async {
      capture.pixel(t);
      final service = PhotoChat();
      ImageSource? selected;
      await t.pumpWidget(
        capture.app(
          ConversationScreen(
            conversationId: 'chat',
            service: service,
            pickPhoto: (source) async {
              selected = source;
              return XFile.fromData(
                photo,
                mimeType: 'image/png',
                name: 'photo.png',
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Attach photo'));
      await t.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      await t.tap(find.text('Choose from gallery'));
      await t.pumpAndSettle();
      expect(selected, ImageSource.gallery);
      expect(find.text('Send photo'), findsOneWidget);
      expect(service.sends, 0);
      await t.tap(find.text('Send photo'));
      await t.pumpAndSettle();
      expect(
        find.text('Photo not sent. Tap Send photo to retry.'),
        findsOneWidget,
      );
      await t.tap(find.text('Send photo'));
      await t.pumpAndSettle();
      expect(service.requests.toSet().length, 1);
      expect(service.sends, 2);
      expect(find.text('Send photo'), findsNothing);
      await capture.proof(t, 'chat-photo');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('camera source can be cancelled without sending a message', (
    t,
  ) async {
    final service = PhotoChat();
    ImageSource? selected;
    await t.pumpWidget(
      capture.app(
        ConversationScreen(
          conversationId: 'chat',
          service: service,
          pickPhoto: (source) async {
            selected = source;
            return null;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Attach photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Take a photo'));
    await t.pumpAndSettle();
    expect(selected, ImageSource.camera);
    expect(service.sends, 0);
    expect(find.text('Send photo'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
