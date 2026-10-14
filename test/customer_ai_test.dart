import 'dart:async';
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
  String chatTitle = 'Cleaning help';
  Completer<void>? pending;
  @override
  Future<void> rename(String id, String title) async {
    chatTitle = title;
  }

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
          {'id': 'conversation', 'title': chatTitle},
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
    await pending?.future;
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
      await t.tap(find.byTooltip('Assistant mode'));
      await t.pumpAndSettle();
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
  testWidgets(
    'pending reply displays sent bubble and animated assistant bubble',
    (t) async {
      capture.pixel(t);
      final service = FakeAi()..pending = Completer<void>();
      await t.pumpWidget(
        capture.app(CustomerAiScreen(service: service, speech: FakeSpeech())),
      );
      await t.enterText(find.byType(TextField), 'Find a cleaner');
      await t.tap(find.byTooltip('Send message'));
      await t.pump(const Duration(milliseconds: 350));
      expect(find.text('Find a cleaner'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-thinking-bubble')), findsOneWidget);
      expect(find.text('Thinking…'), findsOneWidget);
      await capture.proof(t, 'ai-thinking-redesign');
      service.pending!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-thinking-bubble')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('history can search rename and reopen a chat', (t) async {
    capture.pixel(t);
    final service = FakeAi();
    await t.pumpWidget(
      capture.app(CustomerAiScreen(service: service, speech: FakeSpeech())),
    );
    await capture.proof(t, 'ai-welcome-redesign');
    await t.tap(find.byTooltip('Chat history'));
    await t.pumpAndSettle();
    await capture.proof(t, 'ai-history-redesign');
    await t.tap(find.byTooltip('Chat options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Rename'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Cleaning help'),
      'Weekend cleaning',
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(service.chatTitle, 'Weekend cleaning');
    await t.enterText(
      find.widgetWithText(TextField, 'Search chats'),
      'plumber',
    );
    await t.pump();
    expect(find.text('No chats match your search.'), findsOneWidget);
    await t.tap(find.byTooltip('Clear search'));
    await t.pump();
    await t.tap(find.text('Weekend cleaning'));
    await t.pumpAndSettle();
    expect(find.text('Weekend cleaning'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('composer fits a narrow phone with keyboard and larger text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      capture.app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            viewInsets: EdgeInsets.only(bottom: 200),
            textScaler: TextScaler.linear(1.4),
          ),
          child: CustomerAiScreen(service: FakeAi(), speech: FakeSpeech()),
        ),
      ),
    );
    await t.tap(find.byTooltip('Assistant mode'));
    await t.pumpAndSettle();
    await t.tap(find.text('Do it for me'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Help me book');
    await t.pump();
    expect(t.takeException(), isNull);
  });
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
      expect(
        t.getCenter(find.byType(AiHalo)).dy,
        lessThan(t.getCenter(find.byIcon(Icons.explore_outlined)).dy),
      );
      await capture.proof(t, 'ai-raised-nav');
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
      expect(
        find.widgetWithText(TextField, 'Compare cleaning services'),
        findsOneWidget,
      );
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
      await t.tap(find.byTooltip('Chat options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
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
