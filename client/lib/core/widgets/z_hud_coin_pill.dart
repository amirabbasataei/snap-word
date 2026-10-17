import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';

/// The HUD coin balance (canvas `ZHomeA` / `ZOverA`): a chunky pill with the
/// amber coin overhanging its start edge. With an [onTap] it is a 44dp tap
/// target and carries the teal «+» affordance; without one it is a plain
/// read-out (no «+», no button semantics).
class ZHudCoinPill extends StatelessWidget {
  final int coins;
  final VoidCallback? onTap;

  const ZHudCoinPill({super.key, required this.coins, this.onTap});

  static TextStyle _hudText(BuildContext context) =>
      ZTypography.button.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w900,
        color: context.z.ink,
      );

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final tappable = onTap != null;
    // The whole pill is the tap target (44 high); the "+" is its affordance.
    return Semantics(
      button: tappable,
      label:
          tappable ? 'سکه‌ها؛ خرید سکه' : 'سکه‌ها: ${toPersianDigits(coins)}',
      excludeSemantics: !tappable,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: ZHitTarget.min,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ZChunkPill(
                  fill: z.surface,
                  depth: ZGame.depthSm,
                  borderWidth: ZGame.outline,
                  height: ZGame.hudPill,
                  // 3 stroke + 4 padding + the coin's 16px of in-flow width.
                  padding: EdgeInsetsDirectional.only(
                    start: 20,
                    end: tappable ? 4 : 14,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      Text(
                        formatPersianNumber(coins),
                        style: _hudText(context),
                      ),
                      if (tappable) ...[
                        const SizedBox(width: 8),
                        ChunkyBox(
                          fill: z.teal,
                          depth: 0,
                          radius: 8,
                          width: 24,
                          height: 24,
                          borderWidth: 2,
                          highlight: false,
                          alignment: Alignment.center,
                          child: Text(
                            '+',
                            style: ZTypography.button.copyWith(
                              fontSize: 17,
                              height: 1,
                              color: z.onTeal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // The coin overhangs the pill's start edge by 14.
                PositionedDirectional(
                  start: -7,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ChunkyBox(
                      fill: z.amber,
                      circle: true,
                      depth: 0,
                      width: 30,
                      height: 30,
                      borderWidth: ZGame.outlineInner,
                      alignment: Alignment.center,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: z.amberDeep, width: 2.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
