import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/screens/support/customer_support_screen.dart';
import 'package:fyp2/Customer/screens/support/customer_information_screen.dart';
import 'package:fyp2/Customer/services/customer_support_service.dart';
import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'customer_accounts_chat_test.dart' as capture;

class SupportFixture extends CustomerSupportService {
  int attempts = 0;
  final ids = <String>[];
  List<SupportPhoto> photos = [];
  @override
  Future<String> send({
    required String requestId,
    String? bookingId,
    required String subject,
    required String description,
    required List<SupportPhoto> photos,
  }) async {
    attempts++;
    ids.add(requestId);
    this.photos = photos;
    if (attempts == 1)
      throw const FormatException(
        'Please check your connection and try again.',
      );
    return 'ticket-1';
  }

  @override
  Future<List<Map<String, dynamic>>> requests({
    String? id,
    int offset = 0,
  }) async => [
    {
      'dispute_id': 'ticket-1',
      'subject': 'Help updating my service address',
      'description':
          'I need to change the unit number for my upcoming service.',
      'status': 'Under Review',
      'created_at': '2026-10-18T06:00:00Z',
      'resolution':
          'Please open My Addresses and select the address you want to update.',
      'attachment_paths': <String>[],
    },
  ];
}

void main() {
  late Uint8List fixturePhoto;
  setUpAll(() async {
    fixturePhoto = (await rootBundle.load(
      'assets/brand/home-serve-mark.png',
    )).buffer.asUint8List();
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))).load();
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty)
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
  });

  test('lost final response recovers ticket without uploading again', () async {
    var submitted = false, uploads = 0, submissions = 0;
    final transport = MockClient((request) async {
      http.Response response(Object body) => http.Response(
        jsonEncode(body),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
      if (request.url.path.endsWith('/token'))
        return response(capture.session());
      if (request.url.path.endsWith('/customer_prepare_support')) {
        return response({'dispute_id': submitted ? 'saved-ticket' : null});
      }
      if (request.url.path.contains('/storage/v1/object/support-photos/')) {
        uploads++;
        return response({'Key': 'photo'});
      }
      if (request.url.path.endsWith('/customer_submit_support')) {
        submissions++;
        submitted = true;
        throw const SocketException('Simulated lost response');
      }
      throw StateError(request.url.toString());
    });
    final client = SupabaseClient(
      'https://fixture.invalid',
      'test',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      await client.auth.signInWithPassword(
        email: 'fixture@example.invalid',
        password: 'fixture',
      );
      final service = CustomerSupportService(client: client);
      Future<String> send() => service.send(
        requestId: 'request',
        subject: 'Subject',
        description: 'A detailed question',
        photos: [
          SupportPhoto(Uint8List.fromList([255, 216, 255])),
        ],
      );
      await expectLater(send(), throwsA(isA<SocketException>()));
      expect(await send(), 'saved-ticket');
      expect(uploads, 1);
      expect(submissions, 1);
    } finally {
      await client.dispose();
    }
  });

  testWidgets(
    'support form validates, preserves failed submission and retries one request',
    (t) async {
      capture.pixel(t);
      final service = SupportFixture();
      String? result;
      await t.pumpWidget(
        capture.app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CustomerSupportComposeScreen(
                        service: service,
                        bookingId: 'booking-1',
                      ),
                    ),
                  );
                },
                child: const Text('Open support'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open support'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(service.attempts, 0);
      expect(find.text('Enter at least 3 characters'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('support-subject')),
        'Service quality question',
      );
      await t.enterText(
        find.byKey(const ValueKey('support-description')),
        'The repaired tap is still leaking. Please help me resolve this.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(service.attempts, 1);
      expect(
        t
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('support-subject')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await t.ensureVisible(find.text('Retry sending'));
      await t.tap(find.text('Retry sending'));
      await t.pumpAndSettle();
      expect(result, 'ticket-1');
      expect(service.ids.toSet().length, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('invalid attachment shows error without being submitted', (
    t,
  ) async {
    capture.pixel(t);
    await t.pumpWidget(
      capture.app(
        CustomerSupportComposeScreen(
          service: SupportFixture(),
          pickPhoto: (_) async =>
              XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'bad.png'),
        ),
      ),
    );
    await t.ensureVisible(find.text('Choose photo'));
    await t.tap(find.text('Choose photo'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Choose a JPEG, PNG or WebP photo.'),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('customer can preview and remove a valid photo before sending', (
    t,
  ) async {
    capture.pixel(t);
    await t.pumpWidget(
      capture.app(
        CustomerSupportComposeScreen(
          service: SupportFixture(),
          pickPhoto: (_) async =>
              XFile.fromData(fixturePhoto, name: 'fixture.png'),
        ),
      ),
    );
    await t.ensureVisible(find.text('Choose photo'));
    await t.runAsync(() async {
      await t.tap(find.text('Choose photo'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove photo'), findsOneWidget);
    await t.ensureVisible(find.byTooltip('Remove photo'));
    await t.tap(find.byTooltip('Remove photo'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final language in ['en', 'zh', 'ms']) {
    testWidgets(
      'support and information screens fit narrow displays in $language',
      (t) async {
        capture.pixel(t);
        t.view.physicalSize = const Size(320, 808);
        await AppLanguage.instance.select(language);
        for (final screen in <Widget>[
          CustomerSupportScreen(service: SupportFixture()),
          CustomerSupportComposeScreen(service: SupportFixture()),
          CustomerSupportDetailScreen(
            id: 'ticket-1',
            service: SupportFixture(),
          ),
          const CustomerInformationScreen(privacy: true),
          const CustomerInformationScreen(),
        ]) {
          await t.pumpWidget(capture.app(screen));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          if (language == 'en')
            await capture.proof(t, 'support-${screen.runtimeType}');
          await t.drag(find.byType(ListView).first, const Offset(0, -600));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
        await AppLanguage.instance.select('en');
      },
    );
  }

  testWidgets(
    'reduced motion removes bounce while keeping content scrollable',
    (t) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        capture.app(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: CustomerScaffold(
              body: ListView(
                controller: controller,
                children: const [Text('Short content')],
              ),
            ),
          ),
        ),
      );
      final gesture = await t.startGesture(const Offset(100, 100));
      await gesture.moveBy(const Offset(0, 150));
      await t.pump();
      expect(controller.offset, 0);
      await gesture.up();
      await t.pumpAndSettle();
    },
  );
}
