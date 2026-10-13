import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/screens/ai/customer_ai_screen.dart';
import 'package:fyp2/Customer/screens/home/customer_root_nav_screen.dart';
import 'package:fyp2/Customer/services/customer_ai_service.dart';
import 'package:fyp2/Customer/services/customer_ai_speech.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'customer_receipt_photo_test.dart' as photo;

class FakeSpeech extends CustomerAiSpeech {
  void Function(String)? result;
  bool stopped = false;
  @override
  Future<bool> start(
    void Function(String) text,
    void Function() done,
    void Function() error,
  ) async {
    result = text;
    return true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> cancel() async {
    stopped = true;
  }
}

class FakeAi extends CustomerAiService {
  String? navigationScreen;
  final messages = <Map<String, dynamic>>[];
  final requestIds = <String>[];
  bool fail = false, deleted = false;
  int uploads = 0, confirms = 0;
  String? lastPhoto;
  @override
  Future<Map<String, dynamic>> create(String id) async => {
    'id': 'conversation',
    'title': 'Cleaning help',
  };
  @override
  Future<List<Map<String, dynamic>>> conversations({int offset = 0}) async =>
      deleted
      ? []
      : [
          {'id': 'conversation', 'title': 'Cleaning help'},
        ];
  @override
  Future<List<Map<String, dynamic>>> history(String id, {int? before}) async {
    if (deleted) throw const FormatException('Deleted');
    return List.of(messages);
  }

  @override
  Future<Map<String, dynamic>> send({
    required String conversation,
    required String requestId,
    required String message,
    required String mode,
    String? imagePath,
  }) async {
    requestIds.add(requestId);
    lastPhoto = imagePath;
    if (fail) {
      fail = false;
      throw const FormatException('Temporary failure. Retry.');
    }
    messages.add({'id': 1, 'role': 'user', 'content': message});
    final reply = {
      'id': 2,
      'role': 'assistant',
      'content': 'I can compare cleaners using your saved address.',
      'actions': navigationScreen != null
          ? [
              {
                'kind': 'navigate',
                'screen': navigationScreen,
                'title': 'Open $navigationScreen',
              },
            ]
          : [
              {
                'id': 'draft',
                'kind': 'booking',
                'title': 'Request booking',
                'summary':
                    'Cleaning · Local Provider\nRM 90.00\nTomorrow 09:00 · Home',
                'status': 'pending',
              },
            ],
    };
    messages.add(reply);
    return reply;
  }

  @override
  Future<void> delete(String id) async {
    deleted = true;
    messages.clear();
  }

  @override
  Future<Map<String, dynamic>> confirm(String id) async {
    confirms++;
    return {'status': 'done'};
  }

  @override
  Future<Uint8List> preparePhoto(Uint8List bytes) async => bytes;
  @override
  Future<String> upload(
    String conversation,
    String requestId,
    Uint8List bytes,
  ) async {
    uploads++;
    return 'owned/photo.jpg';
  }
}

void main() {
  testWidgets(
    'Assist opens app screens but never automatically opens payment',
    (t) async {
      capture.pixel(t);
      final service = FakeAi()..navigationScreen = 'bookings';
      final opened = <String>[];
      await t.pumpWidget(
        capture.app(
          CustomerAiScreen(
            service: service,
            speech: FakeSpeech(),
            onNavigate: (action) async {
              opened.add(action['screen'] as String);
            },
          ),
        ),
      );
      await t.tap(find.text('Do it for me'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Open my bookings');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(opened, ['bookings']);
      service.navigationScreen = 'payment';
      await t.enterText(find.byType(TextField), 'Show payment');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(opened, ['bookings']);
      expect(t.takeException(), isNull);
    },
  );
  setUpAll(() async {
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      for (final entry in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            File(
              '$root/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await loader.load();
      }
    }
  });
  testWidgets(
    'central AI entrance preserves the four original tab destinations',
    (t) async {
      capture.pixel(t);
      await t.pumpWidget(
        capture.app(
          const CustomerRootNavScreen(
            pages: [
              Text('Explore content'),
              Text('Bookings content'),
              Text('Notifications content'),
              Text('Profile content'),
            ],
          ),
        ),
      );
      await t.tap(find.text('Notifications'));
      await t.pumpAndSettle();
      expect(find.text('Notifications content'), findsOneWidget);
      await t.tap(find.text('AI'));
      await t.pumpAndSettle();
      expect(find.text('Local Life AI'), findsOneWidget);
      await t.tap(find.byTooltip('Close assistant'));
      await t.pumpAndSettle();
      expect(find.text('Notifications content'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'AI failure retains prompt and same retry identity; action requires explicit confirmation',
    (t) async {
      capture.pixel(t);
      final service = FakeAi()..fail = true;
      await t.pumpWidget(
        capture.app(CustomerAiScreen(service: service, speech: FakeSpeech())),
      );
      await capture.proof(t, 'ai-welcome');
      await t.enterText(find.byType(TextField), 'Compare cleaning services');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(find.text('Temporary failure. Retry.'), findsOneWidget);
      expect(find.text('Compare cleaning services'), findsOneWidget);
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(service.requestIds[0], service.requestIds[1]);
      expect(service.confirms, 0);
      await t.ensureVisible(find.text('Review & confirm'));
      await t.tap(find.text('Review & confirm'));
      await t.pumpAndSettle();
      expect(service.confirms, 0);
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(service.confirms, 0);
      await capture.proof(t, 'ai-booking-card');
      await t.tap(find.text('Review & confirm'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(service.confirms, 1);
      expect(find.text('Completed'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('gallery photo is attached once across a failed send retry', (
    t,
  ) async {
    capture.pixel(t);
    final service = FakeAi()..fail = true;
    await t.pumpWidget(
      capture.app(
        CustomerAiScreen(
          service: service,
          speech: FakeSpeech(),
          pickPhoto: (_) async => photo.PhotoChat().photo('fixture'),
        ),
      ),
    );
    await t.tap(find.byTooltip('Attach photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose from gallery'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove photo'), findsOneWidget);
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    expect(service.uploads, 1);
    expect(service.lastPhoto, 'owned/photo.jpg');
    expect(t.takeException(), isNull);
  });
  testWidgets('hold speech becomes editable text and does not auto send', (
    t,
  ) async {
    capture.pixel(t);
    final speech = FakeSpeech(), service = FakeAi();
    await t.pumpWidget(
      capture.app(CustomerAiScreen(service: service, speech: speech)),
    );
    final gesture = await t.startGesture(
      t.getCenter(find.byTooltip('Hold to speak')),
    );
    await t.pump(const Duration(milliseconds: 700));
    speech.result!('Find a plumber');
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.text('Find a plumber'), findsOneWidget);
    expect(service.requestIds, isEmpty);
    expect(speech.stopped, true);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'chat history selects and deletes conversation with confirmation',
    (t) async {
      capture.pixel(t);
      final service = FakeAi();
      await t.pumpWidget(
        capture.app(CustomerAiScreen(service: service, speech: FakeSpeech())),
      );
      await t.tap(find.byTooltip('Chat history'));
      await t.pumpAndSettle();
      expect(find.text('Cleaning help'), findsOneWidget);
      await t.tap(find.byTooltip('Delete chat'));
      await t.pumpAndSettle();
      expect(service.deleted, false);
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(service.deleted, true);
      expect(find.text('Cleaning help'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
