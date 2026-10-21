import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:fyp2/Customer/screens/home/customer_home_screen.dart';
import 'package:fyp2/Customer/screens/home/customer_root_nav_screen.dart';
import 'package:fyp2/Customer/screens/review/customer_my_reviews_screen.dart';
import 'package:fyp2/Customer/services/customer_home_service.dart';
import 'package:fyp2/Customer/services/customer_address_service.dart';
import 'package:fyp2/Customer/services/customer_review_service.dart';
import 'package:fyp2/Customer/widgets/malaysia_phone_field.dart';
import 'app_language_test.dart' show Host;
import 'customer_accounts_chat_test.dart' as capture;

class HomeFixture extends CustomerHomeService {
  HomeFixture(SupabaseClient client) : super(client: client);
  @override
  Future<Map<String, dynamic>> getCustomerHeaderData() async => {
    'name': 'Wei Ee',
    'address': 'Kuala Lumpur',
  };
  @override
  Future<List<Map<String, dynamic>>> getRecommendedProviders() async => [];
  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [
    for (final name in [
      'Electrical',
      'Plumbing',
      'Window Cleaning',
      'Air-Conditioning',
      'General Cleaning',
      'Cleaning',
    ])
      {'category_name': name, 'category_id': name},
  ];
}

class AddressFixture extends CustomerAddressService {
  AddressFixture(SupabaseClient client) : super(client: client);
  @override
  Future<List<Map<String, dynamic>>> getSavedAddresses() async => [];
}

class SelectableAddresses extends AddressFixture {
  SelectableAddresses(super.client);
  String selected = 'home';
  @override
  Future<List<Map<String, dynamic>>> getSavedAddresses() async => [
    for (final id in ['home', 'office'])
      {
        'address_id': id,
        'label': id == 'home' ? 'Home' : 'Office',
        'address_line': 'Maju Tower, Jalan Tuanku Abdul Rahman',
        'city': 'Kuala Lumpur',
        'state': 'Kuala Lumpur',
        'postcode': '50370',
        'is_default': selected == id,
      },
  ];
  @override
  Future<void> setDefaultAddress(String id, String address) async {
    selected = id;
  }
}

void main() {
  late SupabaseClient client;
  setUpAll(() async {
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
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
  tearDownAll(() => client.dispose());
  tearDown(() => AppLanguage.instance.select('en'));
  testWidgets(
    'Explore address cards preserve selection and keep add action reachable',
    (t) async {
      capture.pixel(t);
      t.view.physicalSize = const Size(320, 720);
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final addresses = SelectableAddresses(client);
      await t.pumpWidget(
        capture.app(
          CustomerHomeScreen(
            homeService: HomeFixture(client),
            addressService: addresses,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Kuala Lumpur'));
      await t.pumpAndSettle();
      expect(find.text('Service Address'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Add service address').hitTestable(), findsOneWidget);
      await capture.proof(t, 'buttons-explore-address');
      await t.scrollUntilVisible(
        find.text('Office'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.tap(find.text('Office'));
      await t.pumpAndSettle();
      expect(addresses.selected, 'office');
      expect(find.byType(BottomSheet), findsNothing);
      await t.tap(find.text('Kuala Lumpur'));
      await t.pumpAndSettle();
      final selected = find.ancestor(
        of: find.text('Office'),
        matching: find.byType(Semantics),
      );
      expect(
        selected.evaluate().any(
          (e) => (e.widget as Semantics).properties.selected == true,
        ),
        isTrue,
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final locale in ['en', 'zh', 'ms']) {
    testWidgets(
      '$locale category cards align and navigation is a single surface',
      (t) async {
        capture.pixel(t);
        t.view.physicalSize = const Size(360, 808);
        await AppLanguage.instance.select(locale);
        await t.pumpWidget(
          capture.app(
            LanguageScope(
              child: Host(
                CustomerRootNavScreen(
                  pages: [
                    CustomerHomeScreen(
                      homeService: HomeFixture(client),
                      addressService: AddressFixture(client),
                    ),
                    const SizedBox(),
                    const SizedBox(),
                    const SizedBox(),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final cards = find.byType(Card);
        expect(cards, findsNWidgets(6));
        final rectangles = [
          for (final element in cards.evaluate())
            t.getRect(find.byWidget(element.widget)),
        ];
        expect(rectangles.map((r) => r.size).toSet(), hasLength(1));
        expect(rectangles[0].top, rectangles[2].top);
        expect(rectangles[3].top, rectangles[5].top);
        expect(find.text(tr('Service Categories')), findsOneWidget);
        expect(find.text(tr('Ordered by customer rating')), findsNothing);
        await capture.proof(t, 'polish-$locale-explore');
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$locale review tabs and phone dialog fit narrow enlarged text',
      (t) async {
        capture.pixel(t);
        t.view.physicalSize = const Size(320, 640);
        await AppLanguage.instance.select(locale);
        final reviews = CustomerMyReviewsScreen(
          service: CustomerReviewService(
            rpc: (_, _) async => <Map<String, dynamic>>[],
          ),
        );
        await t.pumpWidget(
          capture.app(
            LanguageScope(
              child: Host(
                MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 640),
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: reviews,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.drag(find.byType(TabBarView), const Offset(-400, 0));
        await t.pumpAndSettle();
        expect(find.text(tr('No reviews yet.')), findsOneWidget);
        expect(t.takeException(), isNull);
        final controller = TextEditingController(text: '102049818');
        await t.pumpWidget(
          capture.app(
            LanguageScope(
              child: Host(
                MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 640),
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: AlertDialog(
                    scrollable: true,
                    title: Text(tr('Edit {0}', [tr('Phone')])),
                    content: MalaysiaPhoneField(controller: controller),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          t.getSize(find.byType(MalaysiaPhoneField)).height,
          lessThan(140),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
