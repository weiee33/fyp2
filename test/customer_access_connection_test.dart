import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:fyp2/Customer/services/customer_access.dart';
import 'package:fyp2/Customer/widgets/customer_access_host.dart';
import 'mobile_session_restore_test.dart' show RestoreFixture;

class TimeoutFixture extends RestoreFixture {
  @override
  MockClient transport() =>
      MockClient((_) async => throw TimeoutException('Offline'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CustomerAccess> accessFor(
    RestoreFixture fixture, {
    bool active = true,
  }) async {
    await fixture.seed();
    final access = CustomerAccess(client: fixture.client)
      ..accept({'role': 'customer', 'is_active': active});
    addTearDown(() async {
      access.dispose();
      await fixture.client.dispose();
    });
    return access;
  }

  test(
    'offline active account keeps its status and session; reconnect clears warning',
    () async {
      final fixture = RestoreFixture()..offline = true;
      final access = await accessFor(fixture);
      await access.refresh();
      expect(access.customer, true);
      expect(access.unavailable, true);
      expect(access.suspended, false);
      expect(access.denied, false);
      expect(access.restricted, false);
      expect(fixture.client.auth.currentUser?.id, 'customer-id');
      fixture.offline = false;
      await access.refresh();
      expect(access.unavailable, false);
      expect(access.restricted, false);
      expect(
        fixture.requests.where((r) => r.url.path.endsWith('/logout')),
        isEmpty,
      );
    },
  );

  test('timeout is a connection failure, not a suspension', () async {
    final access = await accessFor(TimeoutFixture());
    await access.refresh();
    expect(access.unavailable, true);
    expect(access.restricted, false);
  });

  test('server outage preserves last confirmed active status', () async {
    final fixture = RestoreFixture()..identityStatus = 503;
    final access = await accessFor(fixture);
    await access.refresh();
    expect(access.unavailable, true);
    expect(access.suspended, false);
    expect(access.restricted, false);
  });

  test(
    'offline suspended account stays restricted until confirmed reactivation',
    () async {
      final fixture = RestoreFixture()
        ..offline = true
        ..active = false;
      final access = await accessFor(fixture, active: false);
      await access.refresh();
      expect(access.suspended, true);
      expect(access.restricted, true);
      fixture.offline = false;
      await access.refresh();
      expect(access.unavailable, false);
      expect(access.restricted, true);
      fixture.active = true;
      await access.refresh();
      expect(access.restricted, false);
    },
  );

  test(
    'reconnect applies a suspension made while the client was offline',
    () async {
      final fixture = RestoreFixture()..offline = true;
      final access = await accessFor(fixture);
      await access.refresh();
      expect(access.restricted, false);
      fixture
        ..offline = false
        ..active = false;
      await access.refresh();
      expect(access.unavailable, false);
      expect(access.suspended, true);
      expect(access.restricted, true);
    },
  );

  test(
    'explicit access denial stays blocked across network failures',
    () async {
      final fixture = RestoreFixture()..identityStatus = 403;
      final access = await accessFor(fixture);
      await access.refresh();
      expect(access.denied, true);
      expect(access.unavailable, false);
      expect(access.suspended, false);
      expect(access.restricted, true);
      fixture.offline = true;
      await access.refresh();
      expect(access.unavailable, true);
      expect(access.restricted, true);
      fixture
        ..offline = false
        ..identityStatus = 200;
      await access.refresh();
      expect(access.denied, false);
      expect(access.restricted, false);
    },
  );

  test(
    'a changed canonical role does not leave customer actions enabled',
    () async {
      final fixture = RestoreFixture()..role = 'provider';
      final access = await accessFor(fixture);
      await access.refresh();
      expect(access.denied, true);
      expect(access.suspended, false);
    },
  );

  test(
    'late access response cannot overwrite logout or a newer identity',
    () async {
      final fixture = RestoreFixture()..identityWait = Completer<void>();
      final access = await accessFor(fixture);
      final pending = access.refresh();
      await Future<void>.delayed(Duration.zero);
      access.accept({});
      fixture.identityWait!.complete();
      await pending;
      expect(access.customer, false);
      expect(access.unavailable, false);
    },
  );

  testWidgets(
    'connection banner preserves page, draft and navigation; Retry recovers',
    (t) async {
      final fixture = RestoreFixture();
      final access = await t.runAsync(() => accessFor(fixture));
      await t.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              CustomerAccessHost(access: access, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: TextField()),
                  ),
                ),
                child: const Text('Open draft'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open draft'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Unsent request');
      fixture.offline = true;
      await t.runAsync(access!.refresh);
      await t.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.byType(RestrictedCustomerContent), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Account suspended · View only'), findsNothing);
      expect(find.text('Sign out'), findsNothing);
      expect(find.text('Unsent request'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Still editable');
      fixture.offline = false;
      await t.runAsync(() async {
        await t.tap(find.text('Retry'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsNothing);
      expect(find.text('Still editable'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'confirmed suspension stays red and labelled suspended when offline',
    (t) async {
      final fixture = RestoreFixture()..offline = true;
      final access = await t.runAsync(() => accessFor(fixture, active: false));
      await t.runAsync(access!.refresh);
      await t.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              CustomerAccessHost(access: access, child: child!),
          home: const Scaffold(body: Text('Account page')),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(find.text('Account suspended · View only'), findsOneWidget);
      expect(find.text('Unable to verify account access'), findsNothing);
      expect(find.byType(RestrictedCustomerContent), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
