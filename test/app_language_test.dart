import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:fyp2/shared/localization/language_screen.dart';
import 'package:fyp2/shared/brand/brand_splash.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/screens/profile/customer_settings_screen.dart';
import 'package:fyp2/Customer/widgets/account_widgets.dart';
import 'package:fyp2/Customer/models/booking_model.dart';

class Host extends StatelessWidget {
  final Widget child;
  const Host(this.child, {super.key});
  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: CustomerTheme.lightTheme,
      locale: AppLanguage.instance.locale,
      supportedLocales: AppLanguage.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
  });
  tearDown(() async => AppLanguage.instance.select('en'));

  test(
    'English defaults, invalid saved locales fall back, selection survives restart',
    () async {
      expect(AppLanguage.instance.code, 'en');
      await AppLanguage.instance.select('zh');
      expect(tr('My bookings'), '我的预约');
      await AppLanguage.instance.load();
      expect(AppLanguage.instance.code, 'zh');
      await AppLanguage.instance.select('ms');
      await AppLanguage.instance.load();
      expect(tr('Payment receipt'), 'Resit bayaran');
      expect(() => AppLanguage.instance.select('fr'), throwsArgumentError);
      SharedPreferences.setMockInitialValues({AppLanguage.preferenceKey: 'fr'});
      await AppLanguage.instance.load();
      expect(AppLanguage.instance.code, 'en');
    },
  );

  test(
    'translations have complete matching slots and preserve substituted data',
    () async {
      final catalog =
          jsonDecode(File('assets/l10n/messages.json').readAsStringSync())
              as Map;
      final slots = RegExp(r'\{\d+\}');
      for (final e in catalog.entries) {
        final expected =
            slots.allMatches(e.key as String).map((m) => m.group(0)).toList()
              ..sort();
        expect(e.value, hasLength(2), reason: e.key);
        for (final translation in e.value as List) {
          expect((translation as String).trim(), isNotEmpty, reason: e.key);
          final actual =
              slots.allMatches(translation).map((m) => m.group(0)).toList()
                ..sort();
          expect(actual, expected, reason: e.key);
        }
      }
      await AppLanguage.instance.select('zh');
      expect(tr('Booking {0}', ['Cancel / Jalan 1']), '预约Cancel / Jalan 1');
      expect(tr('Uncatalogued user text {99}'), 'Uncatalogued user text {99}');
      final booking = CustomerBooking.fromJson({
        'booking_id': '123',
        'booking_status': 'Confirmed',
        'payment': {'payment_status': 'Success'},
      });
      expect(booking.status, 'Confirmed');
      expect(booking.paymentStatus, 'Success');
      expect(booking.hasReceipt, isTrue);
    },
  );

  test(
    'action summaries translate fixed copy without changing author-provided values',
    () async {
      await AppLanguage.instance.select('zh');
      final summary = actionSummary({
        'kind': 'booking',
        'summary':
            'Cancel · Provider\nRM 180.00\n2026-10-20 09:00 (Malaysia time)\n1 Jalan Cancel\nInstructions: Cancel\nProvider acceptance is required. Payment is handled by you.',
      });
      expect(summary, contains('Cancel · Provider\nRM 180.00'));
      expect(summary, contains('2026-10-20 09:00 （马来西亚时间）'));
      expect(summary, contains('1 Jalan Cancel\n备注：Cancel'));
      expect(summary, contains('付款由您自行完成'));
      expect(
        actionSummary({'kind': 'set_default_address', 'summary': 'Cancel'}),
        'Cancel',
      );
      final stamp = DateTime.utc(2026, 10, 14, 10);
      expect(
        relativeTime(stamp, now: stamp.add(const Duration(minutes: 3))),
        '3分钟前',
      );
    },
  );

  testWidgets(
    'Save applies language to existing route and back does not save draft',
    (tester) async {
      await tester.pumpWidget(
        LanguageScope(child: const Host(CustomerSettingsScreen())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language / 语言 / Bahasa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('账户设置'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      await tester.tap(find.text('Language / 语言 / Bahasa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bahasa Melayu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(AppLanguage.instance.code, 'zh');
      await tester.tap(find.text('Language / 语言 / Bahasa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bahasa Melayu'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('Tetapan akaun'), findsOneWidget);
      expect(find.text('Bahasa Melayu'), findsOneWidget);
    },
  );

  testWidgets('personal display values are never translated', (tester) async {
    await AppLanguage.instance.select('zh');
    await tester.pumpWidget(
      LanguageScope(
        child: const Host(
          Scaffold(
            body: AccountRow(label: 'Name', value: 'Cancel'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('姓名'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  for (final code in ['en', 'zh', 'ms']) {
    testWidgets('$code language picker fits a narrow phone with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppLanguage.instance.select(code);
      await tester.pumpWidget(
        LanguageScope(
          child: Host(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: const LanguageScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('Bahasa Melayu'), findsOneWidget);
    });
  }

  testWidgets('splash finishes once and reduced motion skips animation', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BrandSplash(
            initialize: () async {
              calls++;
            },
            child: const Text('Ready'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('startup failure provides retry instead of an endless splash', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BrandSplash(
          initialize: () async {
            if (++calls == 1) throw StateError('offline');
          },
          child: const Text('Ready'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(calls, 2);
  });
}
