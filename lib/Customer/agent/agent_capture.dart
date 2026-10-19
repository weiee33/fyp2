import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image;

Uint8List _jpeg(Map<String, Object> p) {
  final pixels = p['bytes'] as Uint8List;
  final frame = image.Image.fromBytes(
    width: p['width'] as int,
    height: p['height'] as int,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    numChannels: 4,
  );
  return Uint8List.fromList(image.encodeJpg(frame, quality: 76));
}

class AgentFrame {
  final Uint8List jpeg;
  final Rect viewport;
  final int viewId;
  const AgentFrame(this.jpeg, this.viewport, this.viewId);
  bool matches(AgentFrame other) =>
      viewport == other.viewport &&
      viewId == other.viewId &&
      listEquals(jpeg, other.jpeg);
}

/// Capture business pixels only; the cursor/border are outside this boundary.
/// GPU readback is awaited; JPEG work runs in an isolate on mobile/desktop.
class AgentCapture {
  final GlobalKey boundaryKey;
  AgentCapture(this.boundaryKey);
  Future<AgentFrame> capture() async {
    await WidgetsBinding.instance.endOfFrame;
    final context = boundaryKey.currentContext;
    final boundary = context?.findRenderObject();
    if (context == null ||
        !context.mounted ||
        boundary is! RenderRepaintBoundary ||
        !boundary.hasSize ||
        !boundary.attached) {
      throw const FormatException('The app screen is not ready.');
    }
    final viewport = boundary.localToGlobal(Offset.zero) & boundary.size;
    final viewId = View.of(context).viewId;
    final ratio = math.min(
      1.5,
      1280 / math.max(boundary.size.width, boundary.size.height),
    );
    final frame = await boundary.toImage(pixelRatio: ratio);
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) {
        throw const FormatException('Unable to capture the app screen.');
      }
      final jpeg = await compute(_jpeg, {
        'bytes': bytes.buffer.asUint8List(),
        'width': frame.width,
        'height': frame.height,
      });
      if (jpeg.length > 1500000) {
        throw const FormatException('The screen image is too large.');
      }
      return AgentFrame(jpeg, viewport, viewId);
    } finally {
      frame.dispose();
    }
  }
}
