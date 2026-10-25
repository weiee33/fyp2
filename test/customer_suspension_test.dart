import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/services/customer_access.dart';
import 'package:fyp2/Customer/widgets/customer_access_host.dart';
import 'package:fyp2/Customer/screens/support/customer_support_screen.dart';

void main() {
  tearDown(() => CustomerAccess.instance.accept(const {}));
  testWidgets(
    'suspension preserves navigation, support routes and reactivation',
    (tester) async {
      var actions = 0, supportActions = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: customerNavigatorKey,
          navigatorObservers: [customerAccessObserver],
          builder: (_, child) => CustomerAccessHost(child: child!),
          home: Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => actions++,
                child: const Text('Book service'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book service'));
      expect(actions, 1);
      CustomerAccess.instance.accept({'role': 'customer', 'is_active': false});
      await tester.pumpAndSettle();
      expect(find.text('Account suspended · View only'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
      final warning = find.text('Account suspended · View only');
      expect(
        tester.getCenter(warning).dx,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
          1,
        ),
      );
      await tester.tap(find.text('Book service'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Help Centre'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomerSupportScreen), findsOneWidget);
      await tester.tap(find.text('Contact Support'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerSupportComposeScreen), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Suspension appeal',
      );
      expect(find.text('Suspension appeal'), findsOneWidget);
      customerNavigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      customerNavigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      customerNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: customerSupportRoute),
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Support test')),
            body: FilledButton(
              onPressed: () => supportActions++,
              child: const Text('Contact Support'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contact Support'));
      expect(supportActions, 1);
      expect(find.text('Account suspended · View only'), findsOneWidget);
      customerNavigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book service'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(actions, 1);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      CustomerAccess.instance.accept({'role': 'customer', 'is_active': true});
      await tester.pumpAndSettle();
      expect(find.text('Account suspended · View only'), findsNothing);
      await tester.tap(find.text('Book service'));
      expect(actions, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('suspension belongs only to canonical customer identity', () {
    final state = CustomerAccess();
    state.accept({'role': 'customer', 'is_active': false});
    expect(state.restricted, isTrue);
    state.accept({'role': 'customer', 'is_active': true});
    expect(state.restricted, isFalse);
    state.accept({'role': 'provider', 'is_active': false});
    expect(state.restricted, isFalse);
    state.dispose();
  });
  testWidgets(
    'restricted content blocks actions but preserves scrolling and passive navigation',
    (tester) async {
      var actions = 0, warnings = 0, navigations = 0;
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestrictedCustomerContent(
              onBlocked: () => warnings++,
              child: Column(
                children: [
                  SuspensionNavigation(
                    child: TextButton(
                      onPressed: () => navigations++,
                      child: const Text('Bookings tab'),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      children: [
                        FilledButton(
                          onPressed: () => actions++,
                          child: const Text('Pay'),
                        ),
                        const TextField(),
                        ...List.generate(
                          40,
                          (i) => SizedBox(
                            height: 60,
                            child: Text('Read-only record $i'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pay'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(actions, 0);
      expect(warnings, 1);
      await tester.tap(find.text('Bookings tab'));
      await tester.pump();
      expect(navigations, 1);
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(100));
      expect(actions, 0);
      final tabPoint = tester.getCenter(find.text('Bookings tab'));
      Navigator.of(tester.element(find.text('Bookings tab'))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(SuspensionNavigation.contains(tabPoint), isFalse);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}
