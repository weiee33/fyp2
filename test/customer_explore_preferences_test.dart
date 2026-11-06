import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/models/customer_explore_preferences.dart';
import 'package:fyp2/Customer/screens/home/customer_home_screen.dart';
import 'package:fyp2/Customer/screens/home/customer_root_nav_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_edit_profile_screen.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_ui_polish_test.dart' as fixtures;

class PreferredHome extends fixtures.HomeFixture {
  PreferredHome(super.client);
  @override
  Future<Map<String, dynamic>> getCustomerHeaderData() async => {
    'name': 'Wei Ee',
    'address': 'Kuala Lumpur',
    'service_preferences': ['Plumbing', 'Electrical'],
  };
}

void main() {
  late SupabaseClient client;
  setUpAll(() async {
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
    const fontRoot = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (fontRoot.isNotEmpty) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$fontRoot/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());
  final catalogue = [
    for (final name in ['Electrical', 'Plumbing', 'Cleaning', 'Plumbing'])
      {'category_name': name, 'category_id': name},
  ];
  List<String> names(List<Map<String, dynamic>> rows) =>
      rows.map((row) => row['category_name'] as String).toList();

  test('ordered preferences hide others and collapse duplicate labels', () {
    expect(
      names(
        CustomerExplorePreferences.categories(catalogue, [
          'Plumbing',
          'Electrical',
        ]),
      ),
      ['Plumbing', 'Electrical'],
    );
    expect(
      names(
        CustomerExplorePreferences.categories(catalogue, [
          'Plumbing',
          'Electrical',
        ], includeOthers: true),
      ),
      ['Plumbing', 'Electrical', 'Cleaning'],
    );
  });
  test(
    'empty and retired preferences show the catalogue; all retain tap order',
    () {
      for (final prefs in [
        <String>[],
        ['Retired'],
      ]) {
        expect(names(CustomerExplorePreferences.categories(catalogue, prefs)), [
          'Electrical',
          'Plumbing',
          'Cleaning',
        ]);
      }
      expect(
        names(
          CustomerExplorePreferences.categories(catalogue, [
            'Cleaning',
            'Plumbing',
            'Electrical',
          ]),
        ),
        ['Cleaning', 'Plumbing', 'Electrical'],
      );
      expect(
        CustomerExplorePreferences.unique([
          ' Plumbing ',
          'plumbing',
          '',
          'Electrical',
        ]),
        ['Plumbing', 'Electrical'],
      );
    },
  );

  testWidgets(
    'Explore expands other categories without changing saved preferences',
    (t) async {
      capture.pixel(t);
      await t.pumpWidget(
        capture.app(
          CustomerHomeScreen(
            homeService: PreferredHome(client),
            addressService: fixtures.AddressFixture(client),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Plumbing'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Plumbing')).dx,
        lessThan(t.getTopLeft(find.text('Electrical')).dx),
      );
      expect(find.text('Cleaning'), findsNothing);
      await capture.proof(t, 'preferred-explore');
      final grid = find.byType(AnimatedSize).first;
      final collapsedHeight = t.getSize(grid).height;
      await t.tap(find.byKey(const ValueKey('explore-other-categories')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 160));
      final intermediateHeight = t.getSize(grid).height;
      expect(intermediateHeight, greaterThan(collapsedHeight));
      await t.pumpAndSettle();
      expect(t.getSize(grid).height, greaterThan(intermediateHeight));
      expect(find.text('Cleaning'), findsOneWidget);
      await t.ensureVisible(
        find.byKey(const ValueKey('explore-other-categories')),
      );
      await t.tap(find.byKey(const ValueKey('explore-other-categories')));
      await t.pumpAndSettle();
      expect(find.text('Cleaning'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'preference chips show tap order and append a reselected service',
    (t) async {
      capture.pixel(t);
      final service = capture.FixtureProfile();
      await t.pumpWidget(
        capture.app(
          CustomerEditProfileScreen(
            profileData: service.data,
            service: service,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Plumbing'));
      await t.pumpAndSettle();
      await t.tap(find.text('Plumbing'));
      await t.pumpAndSettle();
      expect(find.text('1. Cleaning'), findsOneWidget);
      expect(find.text('2. Plumbing'), findsOneWidget);
      await t.tap(find.text('1. Cleaning'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cleaning'));
      await t.pumpAndSettle();
      expect(find.text('1. Plumbing'), findsOneWidget);
      expect(find.text('2. Cleaning'), findsOneWidget);
      await capture.proof(t, 'ordered-preferences');
      expect(t.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'zh', 'ms']) {
    testWidgets('preference editor fits narrow enlarged text in $locale', (
      t,
    ) async {
      capture.pixel(t);
      t.view.physicalSize = const Size(320, 800);
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await AppLanguage.instance.select(locale);
      addTearDown(() => AppLanguage.instance.select('en'));
      final service = capture.FixtureProfile();
      await t.pumpWidget(
        capture.app(
          CustomerEditProfileScreen(
            profileData: service.data,
            service: service,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(FilterChip).last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await capture.proof(t, 'preferences-$locale');
    });
  }

  for (final accessible in [false, true]) {
    testWidgets(
      'navigation scroll behavior with accessibleNavigation=$accessible',
      (t) async {
        capture.pixel(t);
        await t.pumpWidget(
          capture.app(
            MediaQuery(
              data: MediaQueryData(accessibleNavigation: accessible),
              child: CustomerRootNavScreen(
                pages: [
                  ListView(
                    children: [
                      for (var i = 0; i < 40; i++)
                        SizedBox(height: 80, child: Text('Row $i')),
                    ],
                  ),
                  const Text('Bookings page'),
                  const Text('Notifications page'),
                  const Text('Profile page'),
                ],
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final slideFinder = find.byKey(
          const ValueKey('customer-navigation-slide'),
        );
        AnimatedSlide slide() => t.widget<AnimatedSlide>(slideFinder);
        expect(slide().offset, Offset.zero);
        await t.drag(find.byType(ListView), const Offset(0, -300));
        await t.pumpAndSettle();
        expect(slide().offset.dy, accessible ? 0 : greaterThan(1));
        await t.drag(find.byType(ListView), const Offset(0, 160));
        await t.pumpAndSettle();
        expect(slide().offset, Offset.zero);
        await t.tap(find.text('Bookings'));
        await t.pumpAndSettle();
        expect(find.text('Bookings page'), findsOneWidget);
        expect(slide().offset, Offset.zero);
        expect(t.takeException(), isNull);
      },
    );
  }
}
