import 'dart:ui';

enum AgentState { idle, thinking, executing, waiting }

class AgentAction {
  final String action, rationale, text;
  final Offset? target, end;
  const AgentAction(
    this.action,
    this.rationale, {
    this.target,
    this.end,
    this.text = '',
  });
  factory AgentAction.parse(Map<String, dynamic> data) {
    if (data.keys.any(
      (k) => !{
        'action',
        'rationale',
        'target_x',
        'target_y',
        'end_x',
        'end_y',
        'text',
      }.contains(k),
    )) {
      throw const FormatException('Unsupported agent response.');
    }
    final action = data['action'];
    final rationale = data['rationale'];
    if (!{
          'click',
          'drag_scroll',
          'input_text',
          'done',
          'handoff',
          'ask_user',
        }.contains(action) ||
        rationale is! String ||
        rationale.isEmpty ||
        rationale.length > 240) {
      throw const FormatException('Unsupported agent response.');
    }
    Offset point(String x, String y) {
      final a = data[x], b = data[y];
      if (a is! num ||
          b is! num ||
          !a.isFinite ||
          !b.isFinite ||
          a < 0 ||
          a > 1000 ||
          b < 0 ||
          b > 1000) {
        throw const FormatException('Invalid agent coordinates.');
      }
      return Offset(a.toDouble(), b.toDouble());
    }

    if (action == 'input_text' && data['text'] is! String) {
      throw const FormatException('Invalid agent input.');
    }
    final text = data['text'] ?? '';
    if (text is! String ||
        text.length > 500 ||
        text.contains(RegExp(r'[\x00-\x08\x0b-\x1f]'))) {
      throw const FormatException('Invalid agent input.');
    }
    return AgentAction(
      action as String,
      rationale,
      target: {'click', 'drag_scroll', 'input_text'}.contains(action)
          ? point('target_x', 'target_y')
          : null,
      end: action == 'drag_scroll' ? point('end_x', 'end_y') : null,
      text: text,
    );
  }
  static Offset toViewport(Offset normalized, Rect viewport) =>
      viewport.topLeft +
      Offset(
        normalized.dx / 1000 * viewport.width,
        normalized.dy / 1000 * viewport.height,
      );
  static Offset normalize(Offset global, Rect viewport) => Offset(
    (global.dx - viewport.left) / viewport.width * 1000,
    (global.dy - viewport.top) / viewport.height * 1000,
  );
}
