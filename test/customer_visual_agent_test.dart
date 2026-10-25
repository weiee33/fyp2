import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as image;
import 'package:flutter/services.dart';
import 'package:fyp2/Customer/core/customer_theme.dart';
import 'customer_accounts_chat_test.dart' as capture;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/agent/agent_capture.dart';
import 'package:fyp2/Customer/agent/agent_controller.dart';
import 'package:fyp2/Customer/agent/agent_host.dart';
import 'package:fyp2/Customer/agent/agent_protocol.dart';
import 'package:fyp2/Customer/agent/agent_surface.dart';

class FrameFixture extends AgentCapture {
  FrameFixture(this.view) : super(GlobalKey());
  final int view;
  int version = 0;
  Rect viewport = const Rect.fromLTWH(0, 0, 400, 800);
  @override
  Future<AgentFrame> capture() async =>
      AgentFrame(Uint8List.fromList([version]), viewport, view);
}

Map<String, dynamic> action(String name, Offset point, {String? text}) => {
  'action': name,
  'rationale': 'Select the visible control.',
  'target_x': point.dx / 400 * 1000,
  'target_y': point.dy / 800 * 1000,
  if (text != null) 'text': text,
};
Future<void> advance(WidgetTester t, AgentOverlayController c) async {
  for (var n = 0; n < 80 && c.active; n++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> mount(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: AgentSurface(
        name: 'explore',
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    const fontRoot = String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (fontRoot.isNotEmpty) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('$fontRoot/Roboto-Regular.ttf').readAsBytes(),
            ),
          ),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('$fontRoot/MaterialIcons-Regular.otf').readAsBytes(),
            ),
          ),
        );
      await icons.load();
    }
  });
  testWidgets('real screenshot JPEG excludes cursor and status overlay', (
    t,
  ) async {
    capture.pixel(t);
    late AgentOverlayController controller;
    Map<String, dynamic>? payload;
    final reply = Completer<Map<String, dynamic>>();
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('proof'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: CustomerTheme.lightTheme,
          builder: (_, child) => AgentHost(
            child: child!,
            controllerFactory: (cap) => controller = AgentOverlayController(
              capture: cap,
              identity: () => 'fixture',
              predict: (p) {
                payload = p;
                return reply.future;
              },
            ),
          ),
          home: AgentSurface(
            name: 'explore',
            child: Scaffold(
              appBar: AppBar(title: const Text('Local Life Service Assistant')),
              body: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 90),
                  const Text(
                    'What can we help you with?',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Browse bookings'),
                  ).agent('Browse bookings'),
                  const SizedBox(height: 20),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Find trusted services for your home.'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(controller.run('Open my bookings'));
    for (var n = 0; n < 100 && payload == null; n++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(payload, isNotNull);
    final bytes = base64Decode(payload!['image'] as String);
    final decoded = image.decodeJpg(bytes)!;
    expect(decoded.width / decoded.height, closeTo(393 / 808, .005));
    expect(bytes.length, lessThan(1500000));
    // The status panel is dark at this point in the displayed overlay, but
    // pixels captured for the model belong only to the white business app bar.
    final pixel = decoded.getPixel(
      (decoded.width * .8).round(),
      (decoded.height * .015).round(),
    );
    expect(pixel.r, greaterThan(180));
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await t.runAsync(
        () => File(
          '.tools/customer-ui/agent-model-viewport.jpg',
        ).writeAsBytes(bytes),
      );
    }
    await capture.proof(t, 'agent-thinking-overlay');
    controller.state = AgentState.executing;
    controller.status = 'Opening your bookings';
    controller.notifyListeners();
    unawaited(controller.moveCursor!(const Offset(210, 300)));
    await t.pump(const Duration(milliseconds: 300));
    await capture.proof(t, 'agent-executing-overlay');
    controller.stop();
    reply.complete({'action': 'handoff', 'rationale': 'Stopped.'});
    await t.pump(const Duration(seconds: 1));
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
  test('normalization preserves viewport origin and aspect ratio', () {
    const viewport = Rect.fromLTWH(12, 36, 420, 880);
    expect(
      AgentAction.toViewport(const Offset(500, 250), viewport),
      const Offset(222, 256),
    );
    expect(
      AgentAction.normalize(const Offset(222, 256), viewport),
      const Offset(500, 250),
    );
    for (final invalid in [double.nan, double.infinity, -1, 1001, '500']) {
      expect(
        () => AgentAction.parse({
          'action': 'click',
          'rationale': 'Open',
          'target_x': invalid,
          'target_y': 0,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => AgentAction.parse({
        'action': 'click',
        'rationale': 'Open',
        'target_x': 0,
        'target_y': 0,
        'thought': 'private',
      }),
      throwsFormatException,
    );
    expect(
      () => AgentAction.parse({
        'action': 'input_text',
        'rationale': 'Type',
        'target_x': 0,
        'target_y': 0,
      }),
      throwsFormatException,
    );
  });
  testWidgets(
    'real pointer click executes once and final submissions are blocked',
    (t) async {
      var clicks = 0;
      await mount(
        t,
        ElevatedButton(
          onPressed: () => clicks++,
          child: const Text('Open'),
        ).agent('Open'),
      );
      final frame = FrameFixture(t.view.viewId);
      var calls = 0;
      final openPoint = t.getCenter(find.text('Open'));
      final c = AgentOverlayController(
        capture: frame,
        identity: () => 'customer',
        predict: (_) async => calls++ == 0
            ? action('click', openPoint)
            : {'action': 'done', 'rationale': 'Opened.'},
      );
      unawaited(c.run('Open'));
      await advance(t, c);
      expect(clicks, 1);
      expect(c.result, 'Opened.');
      c.dispose();
      await mount(
        t,
        ElevatedButton(
          onPressed: () => clicks++,
          child: const Text('Pay'),
        ).agent('Pay', capability: AgentCapability.handoff),
      );
      final payPoint = t.getCenter(find.text('Pay'));
      final guarded = AgentOverlayController(
        capture: frame,
        identity: () => 'customer',
        predict: (_) async => action('click', payPoint),
      );
      unawaited(guarded.run('Pay'));
      await advance(t, guarded);
      expect(clicks, 1);
      expect(guarded.result, contains('confirm'));
      guarded.dispose();
    },
  );
  testWidgets('input is restricted to the registered text controller', (
    t,
  ) async {
    final text = TextEditingController();
    String? changed;
    await mount(
      t,
      SizedBox(
        width: 280,
        child: TextField(controller: text).agent(
          'Search',
          capability: AgentCapability.input,
          controller: text,
          onInput: (value) => changed = value,
        ),
      ),
    );
    var calls = 0;
    final fieldPoint = t.getCenter(find.byType(TextField));
    final c = AgentOverlayController(
      capture: FrameFixture(t.view.viewId),
      identity: () => 'customer',
      predict: (_) async => calls++ == 0
          ? action('input_text', fieldPoint, text: 'plumbing')
          : {'action': 'done', 'rationale': 'Search entered.'},
    );
    unawaited(c.run('Find plumbing'));
    await advance(t, c);
    expect(text.text, 'plumbing');
    expect(changed, 'plumbing');
    expect(t.takeException(), isNull);
    c.dispose();
    await t.pumpWidget(const SizedBox());
    text.dispose();
  });
  testWidgets('changed pixels and rotated viewport reject late actions', (
    t,
  ) async {
    var taps = 0;
    await mount(
      t,
      ElevatedButton(
        onPressed: () => taps++,
        child: const Text('Open'),
      ).agent('Open'),
    );
    final frame = FrameFixture(t.view.viewId);
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final c = AgentOverlayController(
      capture: frame,
      identity: () => 'customer',
      predict: (_) async => calls++ == 0
          ? pending.future
          : {'action': 'handoff', 'rationale': 'Screen changed.'},
    );
    unawaited(c.run('Open'));
    await t.pump();
    frame.version++;
    frame.viewport = const Rect.fromLTWH(0, 0, 800, 400);
    pending.complete(action('click', t.getCenter(find.text('Open'))));
    await advance(t, c);
    expect(taps, 0);
    expect(calls, 2);
    c.dispose();
  });
  testWidgets('physical touch and lifecycle stop ignore late predictions', (
    t,
  ) async {
    var taps = 0;
    await mount(
      t,
      ElevatedButton(
        onPressed: () => taps++,
        child: const Text('Open'),
      ).agent('Open'),
    );
    for (final touch in [true, false]) {
      final pending = Completer<Map<String, dynamic>>();
      final c = AgentOverlayController(
        capture: FrameFixture(t.view.viewId),
        identity: () => 'customer',
        predict: (_) => pending.future,
      );
      unawaited(c.run('Open'));
      await t.pump();
      if (touch) {
        await t.tapAt(const Offset(20, 600));
      } else {
        c.didChangeAppLifecycleState(AppLifecycleState.paused);
      }
      pending.complete(action('click', t.getCenter(find.text('Open'))));
      await t.pump(const Duration(seconds: 1));
      expect(c.active, isFalse);
      expect(taps, 0);
      c.dispose();
    }
  });
  testWidgets(
    'drag injects real scrolling and cursor ends at the same coordinate',
    (t) async {
      final scroll = ScrollController();
      await mount(
        t,
        ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(height: 70, child: Text('Item $i')),
        ),
      );
      var calls = 0;
      final c = AgentOverlayController(
        capture: FrameFixture(t.view.viewId),
        identity: () => 'customer',
        predict: (_) async => calls++ == 0
            ? {
                ...action('drag_scroll', const Offset(200, 600)),
                'end_x': 500,
                'end_y': 375,
              }
            : {'action': 'done', 'rationale': 'Scrolled.'},
      );
      unawaited(c.run('Scroll'));
      await advance(t, c);
      expect(scroll.offset, greaterThan(200));
      expect(t.takeException(), isNull);
      c.dispose();
      await t.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  testWidgets('unregistered control cannot be clicked', (t) async {
    var taps = 0;
    await mount(
      t,
      ElevatedButton(onPressed: () => taps++, child: const Text('Delete')),
    );
    final deletePoint = t.getCenter(find.text('Delete'));
    final c = AgentOverlayController(
      capture: FrameFixture(t.view.viewId),
      identity: () => 'customer',
      predict: (_) async => action('click', deletePoint),
    );
    unawaited(c.run('Delete'));
    await advance(t, c);
    expect(taps, 0);
    expect(c.result, contains('safely identify'));
    c.dispose();
  });
  testWidgets('global overlay passes idle input through and disposes cleanly', (
    t,
  ) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        builder: (_, child) => AgentHost(child: child!),
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => taps++,
            child: const Text('Tap'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Tap'));
    await t.pump();
    expect(taps, 1);
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
}
