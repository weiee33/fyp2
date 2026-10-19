import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/agent/agent_controller.dart';
import 'package:fyp2/Customer/agent/agent_host.dart';
import 'package:fyp2/Customer/agent/agent_surface.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'customer_visual_agent_test.dart' as fixture;
import 'customer_accounts_chat_test.dart' as capture;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))).load();
    const root = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (root.isNotEmpty) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets(
    'question pauses, panel drags, reply resumes from new capture and saves ordered history',
    (t) async {
      capture.pixel(t);
      late AgentOverlayController c;
      final requests = <Map<String, dynamic>>[];
      final saved = <String>[];
      final frame = fixture.FrameFixture(t.view.viewId);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('proof'),
          child: MaterialApp(
            theme: CustomerTheme.lightTheme,
            debugShowCheckedModeBanner: false,
            builder: (_, child) => AgentHost(
              child: child!,
              controllerFactory: (_) => c = AgentOverlayController(
                capture: frame,
                identity: () => 'customer',
                predict: (p) async {
                  requests.add(p);
                  return requests.length == 1 || requests.length == 3
                      ? {
                          'action': 'ask_user',
                          'rationale': 'Which day would you like your service?',
                        }
                      : {
                          'action': 'handoff',
                          'rationale': 'Please review the booking details.',
                        };
                },
              ),
            ),
            home: const AgentSurface(
              name: 'explore',
              child: Scaffold(body: Center(child: Text('Your services'))),
            ),
          ),
        ),
      );
      c.setRecorder((id, kind, text) async => saved.add('$kind:$text'));
      final run = c.run('Help me book a service');
      await t.pump(const Duration(milliseconds: 100));
      expect(c.waiting, isTrue);
      expect(requests.length, 1);
      final before = t.getTopLeft(find.byKey(const ValueKey('agent-panel')));
      await t.drag(
        find.byKey(const ValueKey('agent-drag-handle')),
        const Offset(-25, 180),
      );
      await t.pump(const Duration(milliseconds: 250));
      expect(c.waiting, isTrue);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('agent-panel'))).dy,
        greaterThan(before.dy + 100),
      );
      expect(c.panelInteracting, isFalse);
      final originalSize = t.getSize(find.byKey(const ValueKey('agent-panel')));
      await t.drag(
        find.byKey(const ValueKey('agent-resize-handle')),
        const Offset(-60, 55),
      );
      await t.pump();
      final resized = t.getSize(find.byKey(const ValueKey('agent-panel')));
      expect(resized.width, lessThan(originalSize.width));
      expect(resized.height, greaterThan(originalSize.height));
      expect(c.waiting, isTrue);
      expect(c.panelInteracting, isFalse);

      await capture.proof(t, 'agent-question-panel');
      await t.enterText(
        find.byKey(const ValueKey('agent-answer')),
        'Tomorrow afternoon',
      );
      frame.version++;
      await t.tap(find.byKey(const ValueKey('agent-send-answer')));
      await fixture.advance(t, c);
      await run;
      expect(requests.length, 2);
      expect(
        (requests.last['history'] as List).single['reply'],
        'Tomorrow afternoon',
      );
      expect(requests.last['image'], isNot(requests.first['image']));
      expect(saved.map((s) => s.split(':').first), [
        'goal',
        'question',
        'reply',
        'result',
      ]);
      expect(c.answer('late'), isFalse);
      await t.pump(const Duration(milliseconds: 400));
      await capture.proof(t, 'agent-restart-panel');
      await t.enterText(
        find.byKey(const ValueKey('agent-answer')),
        'Show my bookings',
      );
      await t.ensureVisible(find.text('Start task'));
      await t.tap(find.text('Start task'));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 100));
      expect(c.waiting, isTrue);
      await t.enterText(
        find.byKey(const ValueKey('agent-answer')),
        'My upcoming bookings',
      );
      await t.ensureVisible(find.text('Send answer'));
      await t.tap(find.text('Send answer'));
      await fixture.advance(t, c);
      expect(requests.length, 4);
      expect(
        (requests.last['history'] as List).single['reply'],
        'My upcoming bookings',
      );
      expect(requests.last['goal'], 'Show my bookings');
      expect(requests.last['run_id'], isNot(requests.first['run_id']));
      expect(saved.last, 'result:Please review the booking details.');
      expect(saved.where((s) => s.startsWith('goal:')).length, 2);

      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stop cancels a panel restart before viewport capture', (
    t,
  ) async {
    await fixture.mount(t, const Text('Services'));
    var predictions = 0;
    final c = AgentOverlayController(
      capture: fixture.FrameFixture(t.view.viewId),
      identity: () => 'customer',
      predict: (_) async {
        predictions++;
        return {'action': 'handoff', 'rationale': 'Review your booking.'};
      },
    );
    final run = c.run('Show bookings', settleViewport: true);
    expect(c.active, isTrue);
    c.stop();
    await t.pump(const Duration(milliseconds: 500));
    await run;
    expect(c.active, isFalse);
    expect(predictions, 0);
    c.dispose();
  });

  testWidgets(
    'stop cancels waiting and failed history retries the same event without duplicates',
    (t) async {
      await fixture.mount(t, const Text('Services'));
      final ids = <String>[];
      var fail = true;
      final c = AgentOverlayController(
        capture: fixture.FrameFixture(t.view.viewId),
        identity: () => 'customer',
        predict: (_) async => {
          'action': 'ask_user',
          'rationale': 'Which address?',
        },
      );
      c.setRecorder((id, kind, text) async {
        ids.add(id);
        if (fail) throw Exception('offline');
      });
      final run = c.run('Find help');
      await t.pump();
      expect(c.waiting, isTrue);
      expect(c.historyError, isTrue);
      c.stop();
      await run;
      fail = false;
      await c.retryHistory();
      expect(c.historyError, isFalse);
      expect(ids.where((id) => id == ids.first).length, greaterThan(1));
      expect(ids.toSet().length, 3);
      expect(c.answer('late'), isFalse);
      c.dispose();
    },
  );

  testWidgets(
    'panel fits a small landscape viewport with keyboard and large text',
    (t) async {
      t.view.physicalSize = const Size(640, 360);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      late AgentOverlayController c;
      await t.pumpWidget(
        MaterialApp(
          theme: CustomerTheme.lightTheme,
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(
              size: Size(640, 360),
              viewInsets: EdgeInsets.only(bottom: 150),
              textScaler: TextScaler.linear(1.6),
            ),
            child: AgentHost(
              child: child!,
              controllerFactory: (_) => c = AgentOverlayController(
                capture: fixture.FrameFixture(t.view.viewId),
                identity: () => 'customer',
                predict: (_) async => {
                  'action': 'ask_user',
                  'rationale':
                      'Which address would you like to use for this service?',
                },
              ),
            ),
          ),
          home: const AgentSurface(
            name: 'explore',
            child: Scaffold(body: Text('Services')),
          ),
        ),
      );
      final run = c.run('Find service');
      await t.pump(const Duration(milliseconds: 200));
      expect(c.waiting, isTrue);
      expect(t.takeException(), isNull);
      c.stop();
      await run;
      await t.pumpWidget(const SizedBox());
    },
  );
}
