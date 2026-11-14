import 'dart:async';
import 'package:flutter/material.dart';

/// Uses a server-observed interval and monotonic elapsed time, not the phone clock.
class ServiceCooldown extends StatefulWidget {
  final DateTime? retryAt;
  final DateTime? serverNow;
  final Widget Function(BuildContext, String?) builder;
  const ServiceCooldown({
    super.key,
    this.retryAt,
    this.serverNow,
    required this.builder,
  });

  @override
  State<ServiceCooldown> createState() => _ServiceCooldownState();
}

class _ServiceCooldownState extends State<ServiceCooldown> {
  final _elapsed = Stopwatch();
  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(ServiceCooldown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retryAt != widget.retryAt ||
        oldWidget.serverNow != widget.serverNow) {
      _reset();
    }
  }

  void _reset() {
    _timer?.cancel();
    _elapsed.reset();
    _duration = widget.retryAt != null && widget.serverNow != null
        ? widget.retryAt!.difference(widget.serverNow!)
        : Duration.zero;
    _elapsed.start();
    if (_duration > Duration.zero) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_remaining <= 0) _timer?.cancel();
        if (mounted) setState(() {});
      });
    }
  }

  int get _remaining =>
      ((_duration - _elapsed.elapsed).inMilliseconds / 1000).ceil();

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _remaining;
    final label = seconds <= 0
        ? null
        : '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return widget.builder(context, label);
  }
}
