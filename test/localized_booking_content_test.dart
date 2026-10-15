import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_detail_screen.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'customer_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
  });
  tearDown(() async => AppLanguage.instance.select('en'));

  for (final locale in ['zh', 'ms']) {
    testWidgets('booking keeps authored text unchanged in $locale', (
      tester,
    ) async {
      await AppLanguage.instance.select(locale);
      tester.view.physicalSize = const Size(393, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = fixtures.booking(status: 'Completed', paid: true)
        ..['service_name'] = 'Cancel'
        ..['business_name'] = 'Home'
        ..['customer_address'] = 'Address'
        ..['special_instructions'] = 'Please wait';
      await tester.pumpWidget(
        LanguageScope(
          child: MaterialApp(
            theme: CustomerTheme.lightTheme,
            locale: AppLanguage.instance.locale,
            supportedLocales: AppLanguage.supported,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: CustomerBookingDetailScreen(
              bookingId: data['booking_id'],
              transactions: CustomerTransactionService(
                rpc: (_, _) async => data,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Please wait'), findsOneWidget);
      expect(find.text(tr('Booking details')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
