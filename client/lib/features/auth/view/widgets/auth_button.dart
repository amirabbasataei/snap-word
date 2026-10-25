import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// The big call-to-action of the two login screens (canvas: teal, 3dp outline,
/// 6dp edge). A null [onTap] — or [busy] — draws the flat resting button
/// (`wash` fill, no edge) and ignores taps.
class ZAuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  /// Shows [busyLabel] and ignores taps while a request is in flight.
  final bool busy;
  final String busyLabel;
  final double height;
  final double radius;
  final double fontSize;
  final double depth;

  const ZAuthButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.busyLabel = 'کمی صبر کن…',
    this.height = 62,
    this.radius = 22,
    this.fontSize = 22,
    this.depth = ZGame.depthLg,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final enabled = onTap != null && !busy;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child:
          enabled
              ? ZDialogButton.primary(
                label: label,
                onTap: onTap,
                height: height,
                radius: radius,
                depth: depth,
                fontSize: fontSize,
              )
              : Semantics(
                button: true,
                enabled: false,
                label: busy ? busyLabel : label,
                excludeSemantics: true,
                child: Padding(
                  // Keep the layout of the raised button so it doesn't jump.
                  padding: EdgeInsets.only(bottom: depth + ZGame.outline),
                  child: ChunkyBox(
                    fill: z.wash,
                    depth: 0,
                    highlight: false,
                    radius: radius,
                    height: height,
                    alignment: Alignment.center,
                    child: Text(
                      busy ? busyLabel : label,
                      maxLines: 1,
                      style: ZTypography.button.copyWith(
                        fontSize: fontSize,
                        height: 1,
                        color: z.ink60,
                      ),
                    ),
                  ),
                ),
              ),
    );
  }
}
