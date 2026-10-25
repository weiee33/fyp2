import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/screens/ai/customer_ai_screen.dart';
import 'package:fyp2/Customer/screens/support/customer_information_screen.dart';
import 'package:fyp2/Customer/screens/support/customer_support_screen.dart';
import 'package:fyp2/Customer/services/customer_access.dart';
import 'package:fyp2/Customer/widgets/customer_access_host.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'customer_ai_test.dart' show FakeAi, FakeSpeech;
import 'customer_support_test.dart' show SupportFixture;
import 'customer_accounts_chat_test.dart' as capture;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))).load();
    await (FontLoader('HomeServeCJK')
          ..addFont(rootBundle.load('assets/fonts/noto-sans-sc-regular.ttf')))
        .load();
    const fontRoot = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (fontRoot.isNotEmpty) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$fontRoot/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  tearDown(() async {
    CustomerAccess.instance.accept({});
    await AppLanguage.instance.select('en');
  });
  for (final locale in ['en', 'zh', 'ms']) {
    testWidgets('$locale long brand headings fit narrow enlarged text', (
      tester,
    ) async {
      capture.pixel(tester);
      tester.view.physicalSize = const Size(320, 808);
      await AppLanguage.instance.select(locale);
      final screens = <String, Widget>{
        'about': const CustomerInformationScreen(),
        'ai': CustomerAiScreen(service: FakeAi(), speech: FakeSpeech()),
      };
      for (final entry in screens.entries) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('proof'),
            child: LanguageScope(
              child: MaterialApp(
                key: ValueKey(entry.key),
                debugShowCheckedModeBanner: false,
                theme: CustomerTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: child!,
                ),
                home: entry.value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale ${entry.key}');
        await capture.proof(tester, 'brand-$locale-${entry.key}');
      }
    });
  }
  testWidgets(
    'suspended support banner is centered and has no refresh control',
    (tester) async {
      capture.pixel(tester);
      CustomerAccess.instance.accept({'role': 'customer', 'is_active': false});
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('proof'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: CustomerTheme.lightTheme,
            navigatorKey: customerNavigatorKey,
            navigatorObservers: [customerAccessObserver],
            builder: (_, child) => CustomerAccessHost(child: child!),
            home: CustomerSupportScreen(service: SupportFixture()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('Account suspended · View only');
      expect(tester.getCenter(title).dx, closeTo(393 / 2, 1));
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(tester.takeException(), isNull);
      await capture.proof(tester, 'suspended-support-centered');
    },
  );
}
