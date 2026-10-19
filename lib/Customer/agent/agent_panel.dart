import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../shared/localization/app_language.dart';
import '../core/customer_theme.dart';
import 'agent_controller.dart';

/// The panel owns its drag/keyboard layout; moving it never moves app content.
class AgentPanel extends StatefulWidget {
  final AgentOverlayController controller;
  const AgentPanel({super.key, required this.controller});
  @override
  State<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends State<AgentPanel> {
  final _reply = TextEditingController();
  Offset? _position;
  String _previousQuestion = '';
  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _send() {
    if (widget.controller.answer(_reply.text)) {
      _reply.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.active && c.result.isEmpty && !c.historyError) {
        c.stopBounds = null;
        return const SizedBox.shrink();
      }
      if (_previousQuestion != c.question) {
        _previousQuestion = c.question;
        _reply.clear();
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final safeTop = media.viewPadding.top + 10;
          final safeBottom =
              math.max(media.viewInsets.bottom, media.viewPadding.bottom) + 10;
          final width = math.min(340.0, constraints.maxWidth - 24);
          final available = math.max(
            80.0,
            constraints.maxHeight - safeTop - safeBottom,
          );
          final scale = media.textScaler.scale(1).clamp(1.0, 2.0);
          final height = math.min(
            available,
            (c.waiting ? 260.0 : 118.0) +
                (scale - 1) * 60 +
                (c.historyError ? 54 : 0),
          );
          final maxX = math.max(12.0, constraints.maxWidth - width - 12),
              maxY = math.max(
                safeTop,
                constraints.maxHeight - safeBottom - height,
              );
          final wanted = _position ?? Offset(maxX, safeTop);
          final position = Offset(
            wanted.dx.clamp(12.0, maxX),
            wanted.dy.clamp(safeTop, maxY),
          );
          c.stopBounds = position & Size(width, height);
          return Stack(
            children: [
              Positioned(
                left: position.dx,
                top: position.dy,
                width: width,
                height: height,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    key: const ValueKey('agent-panel'),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFFFFF8F0),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: CustomerTheme.primary.withValues(alpha: .22),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          key: const ValueKey('agent-drag-handle'),
                          behavior: HitTestBehavior.opaque,
                          onPanDown: (_) => c.panelInteracting = true,
                          onPanStart: (_) => c.panelInteracting = true,
                          onPanUpdate: (details) => setState(
                            () => _position = Offset(
                              ((_position?.dx ?? position.dx) +
                                      details.delta.dx)
                                  .clamp(12.0, maxX),
                              ((_position?.dy ?? position.dy) +
                                      details.delta.dy)
                                  .clamp(safeTop, maxY),
                            ),
                          ),
                          onPanEnd: (_) => c.panelInteracting = false,
                          onPanCancel: () => c.panelInteracting = false,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFFFF8A17),
                                  CustomerTheme.primary,
                                  Color(0xFFEA580C),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.drag_indicator_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        tr(
                                          c.waiting ? 'Your turn' : 'AI Agent',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (c.active)
                                    Text(
                                      '${c.step}/12',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: tr(c.active ? 'Stop' : 'Close'),
                                    onPressed: c.active
                                        ? () => c.stop()
                                        : c.dismiss,
                                    icon: Icon(
                                      c.active
                                          ? Icons.stop_circle_outlined
                                          : Icons.close_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: Align(
                                      key: ValueKey(
                                        c.waiting
                                            ? c.question
                                            : c.status + c.result,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        c.waiting
                                            ? c.question
                                            : tr(
                                                c.active ? c.status : c.result,
                                              ),
                                        key: const ValueKey(
                                          'agent-panel-message',
                                        ),
                                        style: TextStyle(
                                          fontSize: c.waiting ? 15 : 13,
                                          height: 1.4,
                                          color: CustomerTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (c.waiting) ...[
                                    const SizedBox(height: 10),
                                    TextField(
                                      key: const ValueKey('agent-answer'),
                                      controller: _reply,
                                      minLines: 1,
                                      maxLines: 2,
                                      maxLength: 500,
                                      textInputAction: TextInputAction.send,
                                      onSubmitted: (_) => _send(),
                                      decoration: InputDecoration(
                                        hintText: tr('Your answer'),
                                        counterText: '',
                                        filled: true,
                                        fillColor: Colors.white,
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                      key: const ValueKey('agent-send-answer'),
                                      onPressed: _send,
                                      icon: const Icon(
                                        Icons.arrow_upward_rounded,
                                        size: 18,
                                      ),
                                      label: Text(tr('Send answer')),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(42),
                                        backgroundColor: CustomerTheme.primary,
                                      ),
                                    ),
                                  ],
                                  if (c.historyError)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            tr('History not saved'),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: CustomerTheme.primaryDark,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: c.retryHistory,
                                          child: Text(
                                            tr('Retry saving'),
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
