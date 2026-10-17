import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/shared/app_scroll_behavior.dart';
import 'package:fyp2/Customer/widgets/customer_refresh.dart';
import 'package:fyp2/Customer/screens/home/customer_root_nav_screen.dart';
import 'package:fyp2/Customer/screens/home/customer_home_screen.dart';
import 'package:fyp2/Customer/screens/booking/customer_bookings_screen.dart';
import 'package:fyp2/Customer/screens/notifications/customer_notification_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_profile_screen.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_ui_polish_test.dart' as home;
import 'customer_ux_test.dart' as ux;
import 'customer_workflow_test.dart' as booking;

const physics = ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

class LongHome extends home.HomeFixture {
  LongHome(super.client);
  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [
    for (var i = 0; i < 15; i++)
      {
        'category_name': i.isEven ? 'Plumbing' : 'Electrical',
        'category_id': '$i',
      },
  ];
}

void main() {
  late SupabaseClient client;
  tearDownAll(() => client.dispose());
  setUpAll(() async {
    client = SupabaseClient(
      'https://fixture.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))).load();
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

  testWidgets(
    'long drag at bottom never refreshes or moves beyond bounds; top refresh stays single flight',
    (t) async {
      capture.pixel(t);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var calls = 0;
      final pending = Completer<void>();
      await t.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: CustomerRefresh(
              onRefresh: () {
                calls++;
                return pending.future;
              },
              child: ListView.builder(
                controller: controller,
                physics: physics,
                itemExtent: 80,
                itemCount: 30,
                itemBuilder: (_, i) => Text('Row $i'),
              ),
            ),
          ),
        ),
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await t.pump();
      final gesture = await t.startGesture(const Offset(180, 500));
      await gesture.moveBy(const Offset(0, -350));
      await t.pump(const Duration(milliseconds: 800));
      expect(controller.offset, controller.position.maxScrollExtent);
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
      await gesture.up();
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(calls, 0);

      controller.jumpTo(700);
      await t.drag(find.byType(ListView), const Offset(0, 250));
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(calls, 0);
      controller.jumpTo(0);
      await t.pump();
      await t.drag(find.byType(ListView), const Offset(0, 400));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(calls, 1);
      await t.drag(find.byType(ListView), const Offset(0, 400));
      await t.pump(const Duration(milliseconds: 500));
      expect(calls, 1);
      pending.complete();
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(controller.offset, 0);
    },
  );

  testWidgets('reversed conversation gestures cannot refresh either end', (
    t,
  ) async {
    var calls = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      capture.app(
        Scaffold(
          body: CustomerRefresh(
            onRefresh: () async {
              calls++;
            },
            child: ListView.builder(
              controller: controller,
              reverse: true,
              physics: physics,
              itemCount: 30,
              itemExtent: 60,
              itemBuilder: (_, i) => Text('Message $i'),
            ),
          ),
        ),
      ),
    );
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await t.pump();
    await t.drag(find.byType(ListView), const Offset(0, 400));
    await t.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(calls, 0);
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('nested horizontal gestures do not reload their page', (t) async {
    var calls = 0;
    await t.pumpWidget(
      capture.app(
        Scaffold(
          body: CustomerRefresh(
            onRefresh: () async {
              calls++;
            },
            child: ListView(
              physics: physics,
              children: [
                SizedBox(
                  height: 100,
                  child: ListView(
                    key: const ValueKey('carousel'),
                    scrollDirection: Axis.horizontal,
                    physics: physics,
                    children: const [
                      SizedBox(width: 1200, child: Text('Categories')),
                    ],
                  ),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await t.drag(
      find.byKey(const ValueKey('carousel')),
      const Offset(-1000, 0),
    );
    await t.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(calls, 0);
  });

  for (final width in [320.0, 393.0]) {
    testWidgets(
      'all customer tab endings clear the glass overlay at width $width with safe area',
      (t) async {
        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          capture.pixel(t);
          t.view.physicalSize = Size(width, 808);
          t.view.viewPadding = const FakeViewPadding(bottom: 24);
          t.view.padding = const FakeViewPadding(bottom: 24);
          addTearDown(t.view.resetViewPadding);
          addTearDown(t.view.resetPadding);
          final notices = ux.Notices();
          notices.rows.clear();
          notices.rows.addAll([
            for (var i = 0; i < 12; i++)
              {
                'notification_id': '$i',
                'title': 'Notice $i',
                'message': 'Booking update',
                'notification_type': 'Booking Update',
                'is_read': true,
                'created_at': '2026-10-17T00:00:00Z',
              },
          ]);
          await t.pumpWidget(
            capture.app(
              CustomerRootNavScreen(
                pages: [
                  CustomerHomeScreen(
                    homeService: LongHome(client),
                    addressService: home.AddressFixture(client),
                  ),
                  CustomerBookingsScreen(
                    transactions: CustomerTransactionService(
                      rpc: (_, _) async => [
                        for (var i = 0; i < 12; i++)
                          {
                            ...booking.booking(),
                            'booking_id': '$i',
                            'service_name': 'Service $i',
                          },
                      ],
                    ),
                  ),
                  CustomerNotificationScreen(service: notices),
                  CustomerProfileScreen(service: capture.FixtureProfile()),
                ],
              ),
            ),
          );
          await t.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          final nav = find.byKey(
            const ValueKey('customer-floating-navigation'),
          );
          expect(t.getRect(nav).bottom, 808 - 24 - 12);
          expect(find.byType(BackdropFilter), findsOneWidget);
          final tabs = ['Explore', 'Bookings', 'Notifications', 'Profile'];
          final endings = [
            'No verified providers with available services yet.',
            'Service 11',
            'Notice 11',
            'Settings & Help',
          ];
          for (var i = 0; i < tabs.length; i++) {
            await t.tap(find.descendant(of: nav, matching: find.text(tabs[i])));
            await t.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );
            final list = t
                .stateList<ScrollableState>(find.byType(Scrollable))
                .firstWhere(
                  (s) => s.position.axisDirection == AxisDirection.down,
                );
            // The viewport reaches the device bottom, behind the floating bar.
            expect(t.getRect(find.byWidget(list.widget)).bottom, 808);
            if (i == 0 && width == 393) {
              list.position.jumpTo(220);
              await t.pump();
              await capture.proof(t, 'glass-explore-floating');
            }
            list.position.jumpTo(list.position.maxScrollExtent);
            await t.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );
            expect(
              t.getRect(find.text(endings[i])).bottom,
              lessThan(t.getRect(nav).top),
            );
            expect(find.text(endings[i]).hitTestable(), findsOneWidget);
            final finalSurface = switch (i) {
              1 =>
                find
                    .ancestor(
                      of: find.text(endings[i]),
                      matching: find.byType(Card),
                    )
                    .first,
              2 =>
                find
                    .ancestor(
                      of: find.text(endings[i]),
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              3 =>
                find
                    .ancestor(
                      of: find.text(endings[i]),
                      matching: find.byType(ListTile),
                    )
                    .first,
              _ => find.text(endings[i]),
            };
            expect(
              t.getRect(finalSurface).bottom,
              lessThan(t.getRect(nav).top),
            );
            if (width == 393) {
              await capture.proof(t, 'glass-${tabs[i].toLowerCase()}-bottom');
            }
            expect(t.takeException(), isNull);
          }
          await t.pumpWidget(const SizedBox());
        } finally {
          debugDisableShadows = originalShadows;
        }
      },
    );
  }
}
