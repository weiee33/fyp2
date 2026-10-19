import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/customer_transaction_service.dart';
import '../../shared/localization/app_language.dart';
import 'agent_capture.dart';
import 'agent_protocol.dart';
import 'agent_surface.dart';

typedef AgentPredict =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class AgentOverlayController extends ChangeNotifier
    with WidgetsBindingObserver {
  static const pointerId = 2147483000;
  final AgentCapture capture;
  final AgentPredict predict;
  final String? Function() identity;
  final cursor = ValueNotifier<Offset?>(null);
  AgentState state = AgentState.idle;
  String status = '', result = '';
  int step = 0, _epoch = 0;
  bool _disposed = false;
  Rect? stopBounds;
  Rect? viewport;
  Future<void> Function(Offset)? moveCursor;
  Future<void> Function()? tapRipple;
  AgentOverlayController({
    required this.capture,
    AgentPredict? predict,
    String? Function()? identity,
  }) : predict = predict ?? _predict,
       identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id) {
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }
  static Future<Map<String, dynamic>> _predict(
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke('customer-visual-agent', body: body)
          .timeout(const Duration(seconds: 60));
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (e) {
      throw FormatException(
        e.details is Map
            ? e.details['error'].toString()
            : 'AI Agent is unavailable. Please try again.',
      );
    }
  }

  bool get active => state != AgentState.idle;
  void _onPointer(PointerEvent event) {
    if (active && event is PointerDownEvent && event.pointer != pointerId) {
      stop('You took control.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (active && state != AppLifecycleState.resumed) {
      stop('AI Agent stopped when the app left the foreground.');
    }
  }

  void stop([String reason = 'AI Agent stopped.']) {
    _epoch++;
    state = AgentState.idle;
    result = reason;
    cursor.value = null;
    if (!_disposed) notifyListeners();
  }

  void dismiss() {
    result = '';
    notifyListeners();
  }

  bool _valid(int epoch, String user) =>
      !_disposed && epoch == _epoch && active && identity() == user;
  void _phase(AgentState value, String label) {
    state = value;
    status = label;
    notifyListeners();
  }

  List<AgentTargetState> _targets(AgentFrame frame) =>
      AgentTarget.targets.where((t) {
        final b = t.bounds;
        if (b == null ||
            !frame.viewport.contains(b.center) ||
            stopBounds?.contains(b.center) == true) {
          return false;
        }
        final hit = HitTestResult();
        GestureBinding.instance.hitTestInView(hit, b.center, frame.viewId);
        return hit.path.any((entry) => identical(entry.target, t.box));
      }).toList();

  Future<void> run(String goal) async {
    if (active || goal.trim().isEmpty || goal.length > 4000) return;
    final user = identity();
    if (user == null) {
      stop('Sign in to use AI Agent.');
      return;
    }
    final epoch = ++_epoch;
    final runId = CustomerTransactionService.newRequestId();
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    final history = <Map<String, dynamic>>[];
    result = '';
    step = 0;
    _phase(AgentState.thinking, 'Looking at the screen…');
    var unchanged = 0;
    try {
      while (_valid(epoch, user) &&
          step < 12 &&
          DateTime.now().isBefore(deadline)) {
        final surface = AgentSurface.current;
        if (surface == null ||
            !{
              'explore',
              'services',
              'provider',
              'booking_form',
              'bookings',
              'booking_detail',
              'date_picker',
              'address_picker',
            }.contains(surface.widget.name)) {
          stop('This screen needs your control.');
          return;
        }
        if (!surface.widget.ready) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        _phase(AgentState.thinking, 'Looking at the screen…');
        final frame = await capture.capture();
        viewport = frame.viewport;
        if (!_valid(epoch, user)) return;
        if (!identical(surface, AgentSurface.current)) continue;
        final targets = _targets(frame);
        final payload = {
          'run_id': runId,
          'step': ++step,
          'goal': goal.trim(),
          'locale': AppLanguage.instance.code,
          'screen': surface.widget.name,
          'local_choices': surface.widget.localChoices,
          'image': base64Encode(frame.jpeg),
          'targets': targets.take(80).map((t) {
            final b = t.bounds!.intersect(frame.viewport);
            final tl = AgentAction.normalize(b.topLeft, frame.viewport),
                br = AgentAction.normalize(b.bottomRight, frame.viewport);
            return {
              'label': t.widget.label.length > 180
                  ? t.widget.label.substring(0, 180)
                  : t.widget.label,
              'capability': t.widget.capability.name,
              'bounds': [tl.dx, tl.dy, br.dx, br.dy],
            };
          }).toList(),
          'history': history.take(12).toList(),
        };
        notifyListeners();
        final action = AgentAction.parse(await predict(payload));
        if (!_valid(epoch, user)) return;
        if (DateTime.now().isAfter(deadline)) break;
        // A response applies only to exactly the pixels/geometry it observed.
        final current = await capture.capture();
        if (!_valid(epoch, user)) return;
        if (!identical(surface, AgentSurface.current) ||
            !frame.matches(current)) {
          history.add({
            'action': 'stale',
            'result': 'Screen changed; no action executed.',
          });
          continue;
        }
        if (action.action == 'done' || action.action == 'handoff') {
          stop(action.rationale);
          return;
        }
        final point = AgentAction.toViewport(action.target!, frame.viewport);
        if (stopBounds?.contains(point) == true) {
          stop('This control needs your attention.');
          return;
        }
        final target = _resolve(point, frame);
        if (action.action != 'drag_scroll' &&
            !surface.widget.localChoices &&
            target == null) {
          stop('AI Agent could not safely identify that control.');
          return;
        }
        if (target?.widget.capability == AgentCapability.handoff) {
          stop('Please review and confirm this action yourself.');
          return;
        }
        if (action.action == 'input_text' &&
            (target?.widget.capability != AgentCapability.input ||
                target?.widget.controller == null ||
                action.text.length > target!.widget.maxLength)) {
          stop('This text field needs your control.');
          return;
        }
        final end = action.end == null
            ? null
            : AgentAction.toViewport(action.end!, frame.viewport);
        if (end != null && !_safeDrag(point, end, frame)) {
          stop('AI Agent could not safely scroll here.');
          return;
        }
        _phase(AgentState.executing, action.rationale);
        await moveCursor?.call(point);
        if (!_valid(epoch, user)) return;
        // Layout may change during the cursor tween. Never tap the replacement.
        final arrived = await capture.capture();
        if (!_valid(epoch, user)) return;
        if (!frame.matches(arrived) ||
            !identical(surface, AgentSurface.current)) {
          continue;
        }
        if (target != null && !identical(_resolve(point, frame), target)) {
          continue;
        }
        if (end != null) {
          await _drag(point, end, frame.viewId, () => _valid(epoch, user));
        } else {
          await tapRipple?.call();
          if (!_valid(epoch, user)) return;
          _tap(point, frame.viewId);
          if (action.action == 'input_text' &&
              target!.mounted &&
              _valid(epoch, user)) {
            target.widget.controller!.value = TextEditingValue(
              text: action.text,
              selection: TextSelection.collapsed(offset: action.text.length),
            );
            target.widget.onInput?.call(action.text);
            FocusManager.instance.primaryFocus?.unfocus();
          }
        }
        if (!_valid(epoch, user)) return;
        await Future<void>.delayed(const Duration(milliseconds: 750));
        if (!_valid(epoch, user)) return;
        if (AgentSurface.current == null) {
          stop('Continue on this screen yourself.');
          return;
        }
        final after = await capture.capture();
        if (!_valid(epoch, user)) return;
        final changed = !frame.matches(after);
        unchanged = changed ? 0 : unchanged + 1;
        history.add({
          'action': action.action,
          'rationale': action.rationale,
          'result': changed
              ? 'Screen changed; inspect the next screenshot.'
              : 'No visible change.',
        });
        if (unchanged >= 2) {
          stop('The screen is not changing. Please take control.');
          return;
        }
      }
      if (_valid(epoch, user)) {
        stop(
          'Step or time limit reached. Review the screen before continuing.',
        );
      }
    } catch (e) {
      if (_valid(epoch, user)) {
        stop(
          e is FormatException
              ? e.message
              : 'AI Agent could not continue. Please try again.',
        );
      }
    } finally {
      if (!_disposed && epoch == _epoch && identity() != user) {
        stop('Your sign-in changed. AI Agent stopped.');
      }
    }
  }

  AgentTargetState? _resolve(Offset point, AgentFrame frame) {
    final hit = HitTestResult();
    GestureBinding.instance.hitTestInView(hit, point, frame.viewId);
    // Deepest explicit target wins; protects nested final-action controls.
    for (final entry in hit.path) {
      for (final target in AgentTarget.targets) {
        if (target.bounds?.contains(point) == true &&
            identical(entry.target, target.box)) {
          return target;
        }
      }
    }
    return null;
  }

  bool _safeDrag(Offset start, Offset end, AgentFrame frame) {
    final v = frame.viewport;
    final body = Rect.fromLTRB(
      v.left + 12,
      v.top + 100,
      v.right - 12,
      v.bottom - 110,
    );
    return body.contains(start) &&
        body.contains(end) &&
        (start.dx - end.dx).abs() < v.width * .15 &&
        (start.dy - end.dy).abs() >= 30 &&
        stopBounds?.contains(start) != true &&
        stopBounds?.contains(end) != true;
  }

  void _tap(Offset p, int view) {
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(
      PointerDownEvent(pointer: pointerId, position: p, viewId: view),
    );
    binding.handlePointerEvent(
      PointerUpEvent(pointer: pointerId, position: p, viewId: view),
    );
  }

  Future<void> _drag(
    Offset from,
    Offset to,
    int view,
    bool Function() valid,
  ) async {
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(
      PointerDownEvent(pointer: pointerId, position: from, viewId: view),
    );
    var previous = from;
    try {
      for (var i = 1; i <= 24; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (!valid()) return;
        final next = Offset.lerp(
          from,
          to,
          Curves.easeInOutCubic.transform(i / 24),
        )!;
        cursor.value = next;
        binding.handlePointerEvent(
          PointerMoveEvent(
            pointer: pointerId,
            position: next,
            delta: next - previous,
            viewId: view,
            timeStamp: Duration(milliseconds: i * 20),
          ),
        );
        previous = next;
      }
      binding.handlePointerEvent(
        PointerUpEvent(
          pointer: pointerId,
          position: to,
          viewId: view,
          timeStamp: const Duration(milliseconds: 500),
        ),
      );
    } finally {
      if (!valid()) {
        binding.handlePointerEvent(
          PointerCancelEvent(
            pointer: pointerId,
            position: previous,
            viewId: view,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    WidgetsBinding.instance.removeObserver(this);
    cursor.dispose();
    super.dispose();
  }
}
