import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'agent_panel.dart';
import '../core/customer_theme.dart';
import 'agent_capture.dart';
import 'agent_controller.dart';
import 'agent_protocol.dart';
import '../services/customer_access.dart';

class AgentHost extends StatefulWidget {
  final Widget child;
  final AgentOverlayController Function(AgentCapture)? controllerFactory;
  const AgentHost({super.key, required this.child, this.controllerFactory});
  static AgentOverlayController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AgentScope>()?.controller;
  @override
  State<AgentHost> createState() => _AgentHostState();
}

class _AgentHostState extends State<AgentHost> with TickerProviderStateMixin {
  final _captureKey = GlobalKey();
  late final AgentOverlayController controller =
      widget.controllerFactory?.call(AgentCapture(_captureKey)) ??
      AgentOverlayController(capture: AgentCapture(_captureKey));
  late final _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final OverlayEntry _entry = OverlayEntry(builder: _overlay);
  Offset _from = Offset.zero, _to = Offset.zero;
  bool get reduced => MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    controller.addListener(_stateChanged);
    CustomerAccess.instance.addListener(_accessChanged);
    controller.moveCursor = (target) async {
      _from =
          controller.cursor.value ?? (controller.viewport?.center ?? target);
      _to = target;
      _motion.duration = reduced
          ? Duration.zero
          : const Duration(milliseconds: 600);
      try {
        await _motion.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    };
    controller.tapRipple = () async {
      if (!reduced) unawaited(HapticFeedback.selectionClick());
      _ripple.duration = reduced
          ? Duration.zero
          : const Duration(milliseconds: 380);
      _ripple.forward(from: 0);
    };
    _motion.addListener(() {
      if (controller.active) {
        controller.cursor.value = Offset.lerp(
          _from,
          _to,
          Curves.easeInOutCubic.transform(_motion.value),
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stateChanged();
  }

  void _stateChanged() {
    if (!mounted) return;
    if (controller.active) {
      if (reduced) _flow.stop();
      _fade.value = reduced ? 1 : _fade.value;
      if (!reduced) {
        _fade.forward();
        final duration = controller.state == AgentState.executing
            ? const Duration(seconds: 3)
            : const Duration(seconds: 6);
        if (!_flow.isAnimating || _flow.duration != duration) {
          _flow.duration = duration;
          _flow.repeat();
        }
      }
    } else {
      _motion.stop(canceled: true);
      if (reduced) {
        _fade.value = 0;
        _flow.stop();
      } else {
        _fade.reverse().then((_) {
          if (mounted && !controller.active) _flow.stop();
        });
      }
    }
  }

  void _accessChanged() {
    if (CustomerAccess.instance.restricted) {
      controller.stop(
        'Your account is view-only. Contact support in Help Centre.',
      );
    }
    if (mounted) setState(() {});
  }

  Widget _overlay(BuildContext context) => Positioned.fill(
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _AgentPainter(controller, _flow, _fade, _ripple),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomerActionTheme(child: AgentPanel(controller: controller)),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => _AgentScope(
    controller: controller,
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _captureKey, child: widget.child),
        Offstage(
          offstage: CustomerAccess.instance.restricted,
          child: Overlay(initialEntries: [_entry]),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    CustomerAccess.instance.removeListener(_accessChanged);
    _entry.remove();
    _entry.dispose();
    controller.removeListener(_stateChanged);
    controller.dispose();
    _flow.dispose();
    _fade.dispose();
    _motion.dispose();
    _ripple.dispose();
    super.dispose();
  }
}

class _AgentScope extends InheritedWidget {
  final AgentOverlayController controller;
  const _AgentScope({required this.controller, required super.child});
  @override
  bool updateShouldNotify(_AgentScope oldWidget) =>
      controller != oldWidget.controller;
}

class _AgentPainter extends CustomPainter {
  final AgentOverlayController controller;
  final Animation<double> flow, fade, ripple;
  _AgentPainter(this.controller, this.flow, this.fade, this.ripple)
    : super(
        repaint: Listenable.merge([
          controller,
          controller.cursor,
          flow,
          fade,
          ripple,
        ]),
      );
  @override
  void paint(Canvas canvas, Size size) {
    if (fade.value <= 0) return;
    final rect = (Offset.zero & size).deflate(3);
    final border = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    final breathing = .72 + .24 * math.sin(flow.value * math.pi * 2);
    final alpha = fade.value * breathing;
    final shader = SweepGradient(
      colors: const [
        Color(0xFF18DFFF),
        Color(0xFF635BFF),
        Color(0xFFEF4BFF),
        Color(0xFFFF8A17),
        Color(0xFFFF55A8),
        Color(0xFF18DFFF),
      ],
      transform: GradientRotation(flow.value * math.pi * 2),
    ).createShader(rect);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRRect(
      border,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..shader = shader
        ..color = Colors.white.withValues(alpha: alpha * .7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      border,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..shader = shader
        ..color = Colors.white.withValues(alpha: alpha),
    );
    // Soft moving highlights follow the rounded perimeter without rotating its geometry.
    final path = Path()..addRRect(border);
    final metric = path.computeMetrics().first;
    for (var i = 0; i < 3; i++) {
      final start = ((flow.value + i / 3) % 1) * metric.length;
      final end = math.min(metric.length, start + metric.length * .13);
      canvas.drawPath(
        metric.extractPath(start, end),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = [
            const Color(0xFF85F5FF),
            const Color(0xFFFFB0E4),
            const Color(0xFFFFBC75),
          ][i].withValues(alpha: alpha * .8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    final globalPoint = controller.cursor.value;
    final point = globalPoint == null
        ? null
        : globalPoint - (controller.viewport?.topLeft ?? Offset.zero);
    if (point != null) {
      canvas.drawCircle(
        point,
        15,
        Paint()
          ..color = const Color(0xFF48E5FF).withValues(alpha: .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        point,
        10,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFFFF6B00));
      if (ripple.value > 0 && ripple.value < 1) {
        canvas.drawCircle(
          point,
          12 + 26 * ripple.value,
          Paint()
            ..color = const Color(
              0xFF48E5FF,
            ).withValues(alpha: 1 - ripple.value)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - ripple.value),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AgentPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
