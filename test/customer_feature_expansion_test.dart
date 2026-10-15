import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:fyp2/shared/chat/chat_photo.dart';
import 'package:fyp2/Customer/services/provider_coverage_service.dart';
import 'package:fyp2/Customer/services/customer_review_service.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/Customer/screens/review/customer_my_reviews_screen.dart';
import 'package:fyp2/Customer/screens/payment/customer_checkout_screen.dart';
import 'package:fyp2/Customer/screens/home/add_address_map_screen.dart';
import 'customer_receipt_photo_test.dart' as photos;
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_workflow_test.dart' as fixtures;
import 'customer_ux_test.dart' as addresses;

void main() {
  setUpAll(() async {
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      for (final entry in {
        'Roboto': 'roboto-regular.ttf',
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
  testWidgets(
    'gallery swipes both ways and retains initial photo when earlier photos arrive',
    (t) async {
      capture.pixel(t);
      await t.pumpWidget(
        capture.app(
          ChatPhotoGallery(
            paths: const ['b', 'c'],
            initialPath: 'b',
            service: photos.PhotoChat(),
            loadEarlier: () async => ['a'],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 2 of 3'), findsOneWidget);
      await t.drag(find.byType(PageView), const Offset(-500, 0));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 3 of 3'), findsOneWidget);
      await t.drag(find.byType(PageView), const Offset(500, 0));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 2 of 3'), findsOneWidget);
      await t.tap(find.byTooltip('Previous photo'));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 1 of 3'), findsOneWidget);
      await capture.proof(t, 'gallery-swipe');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('review hub exposes completed paid services and prior reviews', (
    t,
  ) async {
    capture.pixel(t);
    await t.pumpWidget(
      capture.app(
        CustomerMyReviewsScreen(
          service: CustomerReviewService(
            rpc: (name, _) async => name == 'customer_review_queue'
                ? [
                    {
                      'booking_id': 'b',
                      'provider_id': 'p',
                      'service_name_snapshot': 'Completed cleaning',
                      'provider_name_snapshot': 'Local Provider',
                    },
                  ]
                : <Map<String, dynamic>>[],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Ready To Review'), findsOneWidget);
    expect(find.text('Completed cleaning'), findsOneWidget);
    expect(find.textContaining('Reviews unlock after payment'), findsNothing);
    expect(find.text('Your Reviews'), findsOneWidget);
    await capture.proof(t, 'review-ready');
    await t.drag(find.byType(TabBarView), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(find.text('No reviews yet.'), findsOneWidget);
    expect(find.text('Completed cleaning'), findsNothing);
    await capture.proof(t, 'review-submitted');
    await t.tap(find.text('Ready To Review'));
    await t.pumpAndSettle();
    expect(find.text('Completed cleaning'), findsOneWidget);
    await capture.proof(t, 'review-ready');
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'alternate payment choice forwards only method and booking to server',
    (t) async {
      capture.pixel(t);
      Map<String, dynamic>? request;
      await t.pumpWidget(
        capture.app(
          CustomerCheckoutScreen(
            bookingId: 'booking',
            launchCheckout: (_) async => true,
            transactions: CustomerTransactionService(
              rpc: (_, _) async => fixtures.booking(status: 'Confirmed'),
              invoke: (_, params) async {
                request = params;
                return {
                  'checkout_url':
                      'https://checkout.stripe.com/c/pay/cs_test_fixture',
                  'test_mode': true,
                };
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Debit / credit card or GrabPay'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Debit / credit card or GrabPay'));
      await t.pumpAndSettle();
      await capture.proof(t, 'payment-method-choices');
      await t.tap(find.text('Open secure payment'));
      await t.pumpAndSettle();
      expect(request, {
        'booking_id': 'booking',
        'payment_option': 'wallet_card',
      });
      expect(find.text('View Receipt'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  test('coverage uses distance from published pin, not customer city text', () {
    final provider = ProviderCoverage({
      'provider_id': 'p',
      'business_name': 'Provider',
      'service_latitude': 3.15,
      'service_longitude': 101.7,
      'service_radius_km': 10,
      'services': ['Cleaning'],
    });
    expect(provider.covers(const LatLng(3.15, 101.7)), true);
    expect(provider.covers(const LatLng(5.4, 100.3)), false);
  });
  testWidgets(
    'map layer has loading error retry and empty states without blocking address',
    (t) async {
      capture.pixel(t);
      var fail = true;
      await t.pumpWidget(
        capture.app(
          AddAddressMapScreen(
            service: addresses.Addresses(),
            locate: () async => const LatLng(3.15, 101.7),
            mapBuilder: (_, _) => const ColoredBox(color: Color(0xFFE6ECE2)),
            coverageService: ProviderCoverageService(
              rpc: (_, _) async {
                if (fail) throw Exception('offline');
                return [];
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Show service areas'));
      await t.pumpAndSettle();
      expect(find.text('Coverage unavailable. Tap to retry.'), findsOneWidget);
      fail = false;
      await t.tap(find.text('Coverage unavailable. Tap to retry.'));
      await t.pumpAndSettle();
      expect(
        find.text('No published service areas near this address.'),
        findsOneWidget,
      );
      await capture.proof(t, 'map-coverage-empty');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
