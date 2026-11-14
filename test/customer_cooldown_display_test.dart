import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/widgets/service_cooldown.dart';
import 'package:fyp2/Customer/widgets/customer_dialogs.dart';
import 'package:fyp2/Customer/screens/browsing/customer_provider_detail_screen.dart';
import 'package:fyp2/Customer/services/customer_browsing_service.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ProviderFixture extends CustomerBrowsingService {
  _ProviderFixture()
    : super(
        client: SupabaseClient(
          'https://fixture.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int calls = 0;
  @override
  Future<Map<String, dynamic>?> getProviderDetails(String providerId) async {
    calls++;
    return {
      'business_name': 'Test provider',
      'services': [
        {
          'service_id': 'service',
          'service_name': 'Install a very long ceiling light fixture',
          'base_price': 50,
          'pricing_type': 'Fixed',
          'estimated_duration': 30,
        },
      ],
      'cooldown_status': {
        'server_now': '2040-01-01T00:00:00Z',
        'cooldowns': [
          {'service_id': 'service', 'retry_at': '2040-01-01T00:25:30Z'},
        ],
      },
    };
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
  });

  testWidgets(
    'server countdown disables booking and expires without phone clock dependence',
    (tester) async {
      final server = DateTime.utc(2040, 1, 1);
      Widget card(Duration remaining) => MaterialApp(
        home: Scaffold(
          body: ServiceCooldown(
            retryAt: server.add(remaining),
            serverNow: server,
            builder: (context, label) => Column(
              children: [
                if (label != null) Text(label),
                ElevatedButton(
                  onPressed: label == null ? () {} : null,
                  child: const Text('Book'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(card(const Duration(minutes: 30)));
      expect(find.text('30:00'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(card(const Duration(milliseconds: 150)));
      expect(find.text('00:01'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:01'), findsNothing);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'email cooldown displays precise Malaysia date, including next-day rollover',
    () {
      final error = PostgrestException(
        message: 'Legacy 14-day message',
        code: 'P0001',
        details: jsonEncode({
          'code': 'email_cooldown',
          'retry_at': '2026-11-28T17:45:00Z',
        }),
      );
      expect(
        CustomerDialogs.errorMessage(error),
        'You can register with this email from 29 Nov 2026, 1:45:00 AM (Malaysia time).',
      );
      expect(
        CustomerDialogs.errorMessage(
          const PostgrestException(message: 'Fallback', details: 'bad-json'),
        ),
        'Fallback',
      );
    },
  );

  testWidgets(
    'service card places countdown beside a wrapping title and refreshes on resume',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _ProviderFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: CustomerTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: CustomerProviderDetailScreen(
            providerId: 'provider',
            heroTag: 'provider',
            browsingService: service,
          ),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('25:30'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.getTopLeft(find.text('25:30')).dx,
        greaterThan(
          tester
              .getTopLeft(
                find.text('Install a very long ceiling light fixture'),
              )
              .dx,
        ),
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(service.calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
