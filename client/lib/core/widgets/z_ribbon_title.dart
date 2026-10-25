import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// Screen title on a swallow-tail ribbon (canvas `ZLobbyA` header): a chunky
/// accent plate with a notched tail poking out of each end, in the accent's
/// deep colour and outlined like every other game object.
///
/// Sizes itself to the text and scales the text down (never wraps) when the
/// space it is given is narrower than that, so it can sit in a header row
/// between a back button and a coin pill on a 320dp phone. The label ignores
/// text scaling above 1.3× — the plate is a fixed 44dp tall.
class ZRibbonTitle extends StatelessWidget {
  final String text;
  final ZDialogAccent accent;

  const ZRibbonTitle(this.text, {super.key, this.accent = ZDialogAccent.coral});

  static const height = 44.0;
  static const depth = 4.0;
  static const tailWidth = 30.0;
  static const tailHeight = 34.0;

  /// How far a tail sticks out past the plate.
  static const tailReach = 20.0;
  static const _tailTop = 12.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (fill, deep, on) = switch (accent) {
      ZDialogAccent.teal => (z.teal, z.tealDeep, z.onTeal),
      ZDialogAccent.indigo => (z.indigo, z.indigoDeep, z.onIndigo),
      ZDialogAccent.amber => (z.amber, z.amberDeep, z.onAmber),
      ZDialogAccent.coral => (z.coral, z.coralDeep, z.onCoral),
    };
    final outline = context.zs.outline;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    // The tails are mirror images: the notch always faces away from the plate.
    Widget tail({required bool atStart}) {
      final notchOnRight = atStart == rtl;
      return PositionedDirectional(
        start: atStart ? 0 : null,
        end: atStart ? null : 0,
        top: _tailTop,
        width: tailWidth,
        height: tailHeight,
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _TailPainter(
              fill: deep,
              outline: outline,
              notchOnRight: notchOnRight,
            ),
          ),
        ),
      );
    }

    return Semantics(
      header: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            tail(atStart: true),
            tail(atStart: false),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                tailReach,
                0,
                tailReach,
                depth + ZGame.outline,
              ),
              child: ChunkyBox(
                fill: fill,
                deep: deep,
                depth: depth,
                radius: 12,
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: ZTypography.button.copyWith(fontSize: 19, color: on),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ribbon tail: a 30×34 flag with a V cut out of its [notchOnRight] edge,
/// filled and stroked (3dp, round joins — the stroke spills past the box).
class _TailPainter extends CustomPainter {
  final Color fill;
  final Color outline;
  final bool notchOnRight;

  const _TailPainter({
    required this.fill,
    required this.outline,
    required this.notchOnRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..lineTo(w - 9, h / 2)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
    if (!notchOnRight) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ZGame.outline
        ..strokeJoin = StrokeJoin.round
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.fill != fill ||
      old.outline != outline ||
      old.notchOnRight != notchOnRight;
}
