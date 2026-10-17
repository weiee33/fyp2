import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/screens/profile/customer_edit_profile_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_settings_screen.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_form_screen.dart';
import 'package:fyp2/Customer/screens/home/customer_root_nav_screen.dart';
import 'package:fyp2/Customer/screens/auth/customer_login_screen.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/shared/brand/brand_splash.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_booking_layout_test.dart' as booking;
import 'customer_ux_test.dart' as ux;

class LongAddresses extends booking.Addresses {
  @override
  Future<List<Map<String, dynamic>>> getSavedAddresses() async => [
    {
      'address_id': 'first',
      'label': 'Home',
      'address_line': 'Maju Tower, Jalan Tuanku Abdul Rahman',
      'city': 'Kuala Lumpur',
      'postcode': '50370',
    },
    {
      'address_id': 'second',
      'label': 'Office',
      'address_line': 'Unit 18, Jalan Bestari 23',
      'city': 'Jenjarom',
      'postcode': '42600',
    },
  ];
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))).load();
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty)
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
  });

  testWidgets(
    'gender picker highlights current value and preserves chosen value on profile',
    (t) async {
      capture.pixel(t);
      final service = capture.FixtureProfile();
      await t.pumpWidget(
        capture.app(
          CustomerEditProfileScreen(
            service: service,
            profileData: service.data,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Gender'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await capture.proof(t, 'refresh-gender');
      await t.tap(find.text('Female'));
      await t.pumpAndSettle();
      expect(find.text('Female'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'long addresses stay readable and selected booking address changes',
    (t) async {
      capture.pixel(t);
      t.view.physicalSize = const Size(320, 720);
      await t.pumpWidget(
        capture.app(
          CustomerBookingFormScreen(
            serviceData: const {
              'service_id': 'service',
              'service_name': 'Pipe Repair',
              'base_price': 100,
            },
            providerData: const {'business_name': 'Local Plumbing'},
            addresses: LongAddresses(),
            transactions: CustomerTransactionService(
              rpc: (_, _) async => <dynamic>[],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('service-address-picker')));
      await t.pumpAndSettle();
      expect(find.text('Service Address'), findsOneWidget);
      expect(
        find.text('Maju Tower, Jalan Tuanku Abdul Rahman, Kuala Lumpur, 50370'),
        findsNWidgets(2),
      );
      await capture.proof(t, 'refresh-address-picker');
      await t.tap(find.text('Office'));
      await t.pumpAndSettle();
      expect(
        find.text('Unit 18, Jalan Bestari 23, Jenjarom, 42600'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'address line grows with its content and floating label aligns to the top',
    (t) async {
      capture.pixel(t);
      await t.pumpWidget(capture.app(ux.map(ux.Addresses())));
      await t.pumpAndSettle();
      final finder = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Address Line / Unit No.',
      );
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      final field = t.widget<TextField>(finder);
      expect(field.minLines, 1);
      expect(field.decoration!.alignLabelWithHint, isTrue);
      await t.enterText(finder, 'Unit 12, Jalan Sungai Rambai');
      await t.pumpAndSettle();
      await capture.proof(t, 'refresh-address-field');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'settings removes alerts and language preview, login uses the house brand',
    (t) async {
      capture.pixel(t);
      await t.pumpWidget(capture.app(const CustomerSettingsScreen()));
      await t.pumpAndSettle();
      expect(find.text('Phone Alerts'), findsNothing);
      expect(find.text('English'), findsNothing);
      await capture.proof(t, 'refresh-settings');
      await t.pumpWidget(capture.app(const CustomerLoginScreen()));
      await t.pumpAndSettle();
    await t.runAsync(() => precacheImage(
      const AssetImage('assets/brand/home-serve-mark.png'),
      t.element(find.byType(HomeServeMark)),
    ));
    await t.pump();
      expect(find.byType(HomeServeMark), findsOneWidget);
      expect(
        find.text('Sign in to book household repair & cleaning'),
        findsNothing,
      );
      await capture.proof(t, 'refresh-login');
    },
  );

  testWidgets(
    'floating navigation keeps inset edges and a raised AI action on a narrow screen',
    (t) async {
      capture.pixel(t);
      t.view.physicalSize = const Size(320, 720);
      await t.pumpWidget(
        capture.app(
          const CustomerRootNavScreen(
            pages: [
              Center(child: Text('Explore content')),
              SizedBox(),
              SizedBox(),
              SizedBox(),
            ],
          ),
        ),
      );
      final ai = t.getRect(find.byIcon(Icons.auto_awesome_rounded));
      final home = t.getRect(find.byIcon(Icons.explore_outlined));
      expect(ai.center.dy, lessThan(home.center.dy));
      await capture.proof(t, 'refresh-floating-nav');
      await t.tap(find.text('Profile'));
      await t.pumpAndSettle();
      expect(find.text('Explore content'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
