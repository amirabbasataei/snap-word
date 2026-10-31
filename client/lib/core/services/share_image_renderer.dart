import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Draws a widget that is not on screen into a PNG.
///
/// The widget is mounted in the root overlay far outside the viewport (never
/// visible, never hit-testable), captured through a [RepaintBoundary], then
/// removed. [size] is the widget's layout size; the image is
/// `size * pixelRatio` pixels.
class ShareImageRenderer {
  const ShareImageRenderer();

  Future<Uint8List> renderPng(
    BuildContext context,
    Widget widget, {
    required Size size,
    double pixelRatio = 3,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final boundaryKey = GlobalKey();
    final entry = OverlayEntry(
      builder:
          (_) => Positioned(
            left: -size.width * 3,
            top: 0,
            width: size.width,
            height: size.height,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(key: boundaryKey, child: widget),
              ),
            ),
          ),
    );
    overlay.insert(entry);
    try {
      // Two frames: layout + first paint, then anything that resolves async.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('share card was not laid out');
      // Debug builds refuse to capture a boundary that has not painted yet.
      var tries = 0;
      while (boundary.debugNeedsPaint && tries++ < 5) {
        await WidgetsBinding.instance.endOfFrame;
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('png encoding failed');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
  }

  /// [renderPng] written to the temp directory; returns the file's path.
  Future<String> renderToFile(
    BuildContext context,
    Widget widget, {
    required Size size,
    required String name,
    double pixelRatio = 3,
  }) async {
    final bytes = await renderPng(
      context,
      widget,
      size: size,
      pixelRatio: pixelRatio,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
