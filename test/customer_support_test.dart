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
import 'package:fyp2/Customer/models/booking_model.dart';
import 'package:fyp2/Customer/screens/booking/customer_booking_detail_screen.dart';
import 'package:fyp2/Customer/services/customer_transaction_service.dart';
import 'package:fyp2/Customer/widgets/customer_scaffold.dart';
import 'package:fyp2/shared/localization/app_language.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_workflow_test.dart' as workflow;

class SupportFixture extends CustomerSupportService {
  final List<Map<String, dynamic>> refunds;
  SupportFixture({this.refunds = const []});
  int attempts = 0;
  final ids = <String>[];
  final bookingIds = <String?>[];
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
    bookingIds.add(bookingId);
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
      'refunds': refunds,
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

  testWidgets('refund progress is separate from the staff support response', (
    t,
  ) async {
    capture.pixel(t);
    await AppLanguage.instance.select('en');
    await t.pumpWidget(
      capture.app(
        CustomerSupportDetailScreen(
          id: 'ticket-1',
          service: SupportFixture(
            refunds: [
              {
                'refund_id': 'refund-1',
                'amount': 40,
                'status': 'Succeeded',
                'gateway_reference': 're_test',
                'updated_at': '2026-10-25T08:00:00Z',
              },
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Refund status'), findsOneWidget);
    expect(find.text('Succeeded · RM 40.00'), findsOneWidget);
    expect(find.text('Refund reference: re_test'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Support response'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Support response'), findsOneWidget);
    expect(t.takeException(), isNull);
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
      expect(service.bookingIds, ['booking-1', 'booking-1']);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'booking support retains its booking and cancellation needs confirmation',
    (t) async {
      capture.pixel(t);
      final data = workflow.booking(status: 'Confirmed', paid: true);
      final support = SupportFixture();
      final calls = <String>[];
      await t.pumpWidget(
        capture.app(
          CustomerBookingDetailScreen(
            bookingId: data['booking_id'],
            supportService: support,
            transactions: CustomerTransactionService(
              rpc: (name, params) async {
                calls.add(name);
                return data;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Cancel Booking'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Cancel Booking'));
      await t.pumpAndSettle();
      await capture.proof(t, 'booking-support-actions');
      await t.tap(find.text('Cancel Booking'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keep booking'));
      await t.pumpAndSettle();
      expect(calls.every((name) => name == 'customer_booking_detail'), isTrue);
      await t.tap(find.text('Request Booking Support'));
      await t.pumpAndSettle();
      expect(find.text('House cleaning'), findsOneWidget);
      expect(find.text('Local Cleaners'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('support-subject')),
        'Service quality question',
      );
      await t.enterText(
        find.byKey(const ValueKey('support-description')),
        'Please review the work completed for this booking.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Send request'));
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(support.bookingIds, [data['booking_id']]);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
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
    await t.ensureVisible(find.text('Gallery'));
    await t.tap(find.text('Gallery'));
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
    await t.ensureVisible(find.text('Gallery'));
    await t.runAsync(() async {
      await t.tap(find.text('Gallery'));
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
          CustomerSupportComposeScreen(
            service: SupportFixture(),
            bookingId: 'booking-1',
            booking: CustomerBooking.fromJson({
              'booking_id': 'booking-1',
              'service_name': 'Fix Leaking Faucet',
              'business_name': 'Home Repair Services',
              'booking_date': '2026-11-18',
              'scheduled_time': '14:30:00',
            }),
          ),
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
          if (screen is CustomerSupportComposeScreen &&
              screen.bookingId != null) {
            expect(find.text('Fix Leaking Faucet'), findsOneWidget);
            expect(find.text('Home Repair Services'), findsOneWidget);
          }
          if (language == 'en') {
            final suffix =
                screen is CustomerSupportComposeScreen &&
                    screen.bookingId != null
                ? '-booking'
                : '';
            await capture.proof(t, 'support-${screen.runtimeType}$suffix');
          }
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
