import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:fyp2/shared/localization/language_screen.dart';
import 'package:fyp2/shared/portal_entry_screen.dart';
import 'package:fyp2/shared/brand/brand_splash.dart';
import 'package:fyp2/Customer/screens/profile/customer_settings_screen.dart';
import 'package:fyp2/Customer/screens/booking/customer_bookings_screen.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_detail_screen.dart';
import 'package:fyp2/Customer/screens/payment/customer_receipt_screen.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/Customer/services/receipt_pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_language_test.dart' show Host;
import 'customer_receipt_photo_test.dart' show receiptData;
import 'customer_workflow_test.dart' as fixtures;
import 'customer_accounts_chat_test.dart' as capture;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
    for (final entry in {
      'Roboto': 'assets/fonts/roboto-regular.ttf',
      'HomeServeCJK': 'assets/fonts/noto-sans-sc-regular.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  tearDown(() async {
    await AppLanguage.instance.select('en');
  });
  for (final locale in ['en', 'zh', 'ms']) {
    testWidgets(
      '$locale phone screens and receipt export preserve booking values',
      (t) async {
        capture.pixel(t);
        t.view.physicalSize = const Size(360, 808);
        await AppLanguage.instance.select(locale);
        final data = receiptData();
        final booking = Map<String, dynamic>.from(data['booking'] as Map);
        booking['service_name'] = '水管维修 / Pipe repair';
        booking['business_name'] = 'Home Care 服务';
        booking['customer_address'] =
            '18, Jalan Seri Utama, Taman Seri, 56000 Kuala Lumpur';
        data['booking'] = booking;
        final pages = <String, Widget>{
          'portal': const PortalEntryScreen(),
          'settings': const CustomerSettingsScreen(),
          'language': const LanguageScreen(),
          'bookings': CustomerBookingsScreen(
            transactions: CustomerTransactionService(
              rpc: (_, _) async => [
                booking,
                fixtures.booking(status: 'Expired'),
              ],
            ),
          ),
          'booking': CustomerBookingDetailScreen(
            bookingId: 'booking',
            transactions: CustomerTransactionService(
              rpc: (_, _) async => booking,
            ),
          ),
          'receipt': CustomerReceiptScreen(
            bookingId: 'booking',
            transactions: CustomerTransactionService(rpc: (_, _) async => data),
          ),
        };
        for (final page in pages.entries) {
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('proof'),
              child: LanguageScope(
                child: Host(
                  KeyedSubtree(key: ValueKey(page.key), child: page.value),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          if (page.key == 'portal') {
            await t.runAsync(
              () => precacheImage(
                const AssetImage('assets/brand/home-serve-mark.png'),
                t.element(find.byType(PortalEntryScreen)),
              ),
            );
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull, reason: '$locale ${page.key}');
          await capture.proof(t, 'language-$locale-${page.key}');
        }
        await t.runAsync(() async {
          final bytes = await buildReceiptPdf(PaymentReceipt(data));
          expect(bytes.length, greaterThan(1000));
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            await File(
              '.tools/customer-ui/receipt-$locale.pdf',
            ).writeAsBytes(bytes);
          }
        });
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('splash frame', (t) async {
    capture.pixel(t);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('proof'),
        child: LanguageScope(
          child: Host(
            BrandSplash(
              initialize: () async =>
                  Future<void>.delayed(const Duration(seconds: 2)),
              child: const Text('Ready'),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 850));
    await t.pump();
    await capture.proof(t, 'home-serve-splash');
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });
}
