import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/Customer/screens/home/add_address_map_screen.dart';
import 'package:fyp2/Customer/screens/notifications/customer_notification_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_delete_account_screen.dart';
import 'package:fyp2/Customer/screens/profile/customer_settings_screen.dart';
import 'package:fyp2/Customer/services/customer_address_service.dart';
import 'package:fyp2/Customer/services/customer_notification_service.dart';
import 'package:fyp2/Customer/services/customer_account_service.dart';
import 'package:fyp2/Customer/widgets/customer_refresh.dart';

Widget app(Widget child) =>
    MaterialApp(theme: CustomerTheme.lightTheme, home: child);
void pixel(WidgetTester t) {
  t.view.physicalSize = const Size(393, 808);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

class Addresses extends CustomerAddressService {
  Addresses()
    : super(
        client: SupabaseClient(
          'https://fixture.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final points = <LatLng>[];
  Future<Map<String, String>> Function(double, double)? lookup;
  Map<String, String> fields = {
    'addressLine': '10 Jalan Test',
    'city': 'Kuala Lumpur',
    'state': 'Kuala Lumpur',
    'postcode': '50088',
  };
  @override
  Future<Map<String, String>> reverseGeocode(double lat, double lng) async {
    points.add(LatLng(lat, lng));
    return lookup == null ? fields : await lookup!(lat, lng);
  }
}

class Notices extends CustomerNotificationService {
  Notices()
    : super(
        client: SupabaseClient(
          'https://fixture.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final rows = <Map<String, dynamic>>[
    {
      'notification_id': 'one',
      'title': 'Booking accepted',
      'message': 'Ready to pay',
      'notification_type': 'Booking Update',
      'is_read': false,
      'is_pinned': false,
      'created_at': '2026-10-04T00:00:00Z',
    },
    {
      'notification_id': 'two',
      'title': 'Welcome',
      'message': 'Hello',
      'notification_type': 'System',
      'is_read': true,
      'is_pinned': false,
      'created_at': '2026-10-03T00:00:00Z',
    },
  ];
  int pins = 0, deletes = 0;
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> getNotifications() async =>
      rows.map((r) => Map<String, dynamic>.from(r)).toList()..sort(
        (a, b) => (b['is_pinned'] == true ? 1 : 0).compareTo(
          a['is_pinned'] == true ? 1 : 0,
        ),
      );
  @override
  Future<void> setPinned(String id, bool value) async {
    if (fail) throw const FormatException('Pin failed');
    pins++;
    rows.firstWhere((r) => r['notification_id'] == id)['is_pinned'] = value;
  }

  @override
  Future<void> deleteNotification(String id) async {
    deletes++;
    rows.removeWhere((r) => r['notification_id'] == id);
  }
}

class Account extends CustomerAccountService {
  int calls = 0;
  bool fail = false;
  @override
  Future<void> deleteAccount(String password) async {
    calls++;
    if (fail) throw const FormatException('Resolve bookings first');
  }
}

Widget map(Addresses service, {Future<LatLng> Function()? locate}) =>
    AddAddressMapScreen(
      service: service,
      locate: locate ?? () async => const LatLng(3.15, 101.71),
      mapBuilder: (context, select) => GestureDetector(
        key: const ValueKey('map-surface'),
        behavior: HitTestBehavior.opaque,
        onTap: () => select(const LatLng(4.1, 101.2)),
        child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
      ),
    );
Future<void> ready(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 800));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'opening address picker locates once and card drag does not move the map',
    (t) async {
      pixel(t);
      final addresses = Addresses();
      var locationCalls = 0;
      await t.pumpWidget(
        app(
          map(
            addresses,
            locate: () async {
              locationCalls++;
              return const LatLng(3.15, 101.71);
            },
          ),
        ),
      );
      await ready(t);
      expect(locationCalls, 1);
      expect(addresses.points.single.latitude, 3.15);
      expect(find.text('10 Jalan Test'), findsOneWidget);
      final before = t.getSize(find.byKey(const ValueKey('map-surface')));
      await t.drag(find.text('Address Details'), const Offset(0, -200));
      await ready(t);
      expect(addresses.points.length, 1);
      expect(t.getSize(find.byKey(const ValueKey('map-surface'))), before);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('new pin clears missing old address fields', (t) async {
    pixel(t);
    final addresses = Addresses();
    await t.pumpWidget(app(map(addresses)));
    await ready(t);
    expect(find.text('50088'), findsOneWidget);
    addresses.fields = {
      'addressLine': 'New road',
      'city': 'New town',
      'state': '',
      'postcode': '',
    };
    await t.tapAt(const Offset(190, 180));
    await ready(t);
    expect(addresses.points.length, 2);
    expect(find.text('10 Jalan Test'), findsNothing);
    expect(find.text('50088'), findsNothing);
    expect(find.text('New road'), findsOneWidget);
  });
  testWidgets('GPS result cannot override a pin selected while waiting', (
    t,
  ) async {
    pixel(t);
    final addresses = Addresses();
    final gps = Completer<LatLng>();
    await t.pumpWidget(app(map(addresses, locate: () => gps.future)));
    await t.pump();
    await t.tapAt(const Offset(190, 180));
    await ready(t);
    gps.complete(const LatLng(2.0, 102.0));
    await ready(t);
    expect(addresses.points.length, 1);
    expect(addresses.points.single.latitude, 4.1);
  });
  testWidgets(
    'denied GPS uses an OK popup and leaves manual address controls available',
    (t) async {
      pixel(t);
      final addresses = Addresses();
      await t.pumpWidget(
        app(
          map(
            addresses,
            locate: () async => throw const FormatException(
              'Allow location or search manually.',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Allow location or search manually.'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(addresses.points, isEmpty);
      expect(find.byTooltip('Search address'), findsOneWidget);
      expect(find.text('My location'), findsOneWidget);
    },
  );
  testWidgets('notification swipe shows Pin and Delete and persists pin', (
    t,
  ) async {
    pixel(t);
    final service = Notices();
    await t.pumpWidget(app(CustomerNotificationScreen(service: service)));
    await t.pumpAndSettle();
    expect(find.byTooltip('Chats'), findsOneWidget);
    expect(find.byTooltip('Mark all as read'), findsNothing);
    await t.drag(find.text('Welcome'), const Offset(-240, 0));
    await t.pumpAndSettle();
    expect(find.text('Pin'), findsWidgets);
    expect(find.text('Delete'), findsWidgets);
    await t.tap(find.text('Pin').last);
    await t.pumpAndSettle();
    expect(service.pins, 1);
    expect(service.rows.last['is_pinned'], true);
    expect(find.text('Notification pinned.'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.text('Welcome')).dy,
      lessThan(t.getTopLeft(find.text('Booking accepted')).dy),
    );
  });
  testWidgets(
    'notification deletion requires confirmation and cancel keeps row',
    (t) async {
      pixel(t);
      final service = Notices();
      await t.pumpWidget(app(CustomerNotificationScreen(service: service)));
      await t.pumpAndSettle();
      await t.drag(find.text('Booking accepted'), const Offset(-240, 0));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(service.deletes, 0);
      await t.drag(find.text('Booking accepted'), const Offset(-240, 0));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete').first);
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(service.deletes, 1);
      expect(find.text('Notification deleted.'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Booking accepted'), findsNothing);
    },
  );
  testWidgets('settings removes duplicate header chat and address links', (
    t,
  ) async {
    pixel(t);
    await t.pumpWidget(app(const CustomerSettingsScreen()));
    await t.pumpAndSettle();
    expect(find.byTooltip('Chats'), findsNothing);
    expect(find.text('My Addresses'), findsNothing);
    expect(find.text('Account & Security'), findsOneWidget);
  });
  testWidgets(
    'delete account cancellation and server rejection keep customer on page',
    (t) async {
      pixel(t);
      final service = Account()..fail = true;
      await t.pumpWidget(app(CustomerDeleteAccountScreen(service: service)));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'fixture-password');
      await t.tap(find.text('Delete my account'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(service.calls, 0);
      await t.tap(find.text('Delete my account'));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(service.calls, 1);
      expect(find.text('Resolve bookings first'), findsOneWidget);
      expect(find.text('Account deleted'), findsNothing);
    },
  );
  testWidgets(
    'successful deletion only shows success after confirmed server result',
    (t) async {
      pixel(t);
      final service = Account();
      await t.pumpWidget(app(CustomerDeleteAccountScreen(service: service)));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'fixture-password');
      await t.tap(find.text('Delete my account'));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(service.calls, 1);
      expect(find.text('Account deleted'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
  testWidgets('short lists bounce and pull up from bottom refreshes once', (
    t,
  ) async {
    pixel(t);
    var refreshed = 0;
    await t.pumpWidget(
      app(
        Scaffold(
          body: CustomerRefresh(
            onRefresh: () async {
              refreshed++;
            },
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: const [Text('Short list')],
            ),
          ),
        ),
      ),
    );
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pumpAndSettle();
    expect(refreshed, 1);
  });
}
