import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Explicit UI capabilities. A model cannot grant itself access to other widgets.
enum AgentCapability { click, input, handoff }

class AgentSurface extends StatefulWidget {
  final String name;
  final bool ready, localChoices;
  final Widget child;
  const AgentSurface({
    super.key,
    required this.name,
    required this.child,
    this.ready = true,
    this.localChoices = false,
  });
  static final Set<AgentSurfaceState> mountedSurfaces = {};
  static AgentSurfaceState? get current {
    final visible = mountedSurfaces.where(
      (s) =>
          s.mounted &&
          ModalRoute.of(s.context)?.isCurrent == true &&
          s.box?.attached == true,
    );
    return visible.isEmpty ? null : visible.last;
  }

  @override
  State<AgentSurface> createState() => AgentSurfaceState();
}

class AgentSurfaceState extends State<AgentSurface> {
  final _key = GlobalKey();
  RenderBox? get box => _key.currentContext?.findRenderObject() as RenderBox?;
  @override
  void initState() {
    super.initState();
    AgentSurface.mountedSurfaces.add(this);
  }

  @override
  void dispose() {
    AgentSurface.mountedSurfaces.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

class AgentTarget extends StatefulWidget {
  final String label;
  final Widget child;
  final AgentCapability capability;
  final TextEditingController? controller;
  final int maxLength;
  final bool enabled;
  const AgentTarget({
    super.key,
    required this.label,
    required this.child,
    this.capability = AgentCapability.click,
    this.controller,
    this.maxLength = 120,
    this.enabled = true,
  });
  static final Set<AgentTargetState> targets = {};
  @override
  State<AgentTarget> createState() => AgentTargetState();
}

class AgentTargetState extends State<AgentTarget> {
  final _key = GlobalKey();
  RenderBox? get box => _key.currentContext?.findRenderObject() as RenderBox?;
  Rect? get bounds {
    final b = box;
    if (!mounted ||
        !widget.enabled ||
        ModalRoute.of(context)?.isCurrent != true ||
        b == null ||
        !b.attached ||
        !b.hasSize) {
      return null;
    }
    return b.localToGlobal(Offset.zero) & b.size;
  }

  @override
  void initState() {
    super.initState();
    AgentTarget.targets.add(this);
  }

  @override
  void dispose() {
    AgentTarget.targets.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _TargetBox(key: _key, child: widget.child);
}

class _TargetBox extends SingleChildRenderObjectWidget {
  const _TargetBox({super.key, required super.child});
  @override
  RenderProxyBox createRenderObject(BuildContext context) => RenderProxyBox();
}

extension AgentWidget on Widget {
  Widget agent(
    String label, {
    AgentCapability capability = AgentCapability.click,
    TextEditingController? controller,
    int maxLength = 120,
    bool enabled = true,
  }) => AgentTarget(
    label: label,
    capability: capability,
    controller: controller,
    maxLength: maxLength,
    enabled: enabled,
    child: this,
  );
}
