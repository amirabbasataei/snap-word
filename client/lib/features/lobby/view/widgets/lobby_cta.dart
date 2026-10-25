import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// The lobby's one big button (canvas `ZLobbyA`): teal «پیدا کردن حریف» with a
/// play disc and the home Play button's idle pulse. While the queue is open it
/// becomes the neutral «لغو جست‌وجو»; after a failed attempt the same teal
/// button reads «تلاش دوباره».
class LobbyCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// True → the neutral cancel variant (no pulse, no play disc).
  final bool cancel;

  const LobbyCta({
    super.key,
    required this.label,
    required this.onTap,
    this.cancel = false,
  });

  static const height = 70.0;
  static const radius = 24.0;
  static const depth = 7.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child:
          cancel
              ? ZDialogButton.secondary(
                label: label,
                onTap: onTap,
                height: height,
                radius: radius,
                depth: depth,
                icon: SvgPicture.string(
                  '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.ink)}" stroke-width="3.4" stroke-linecap="round"><path d="M5 5l14 14M19 5L5 19"/></svg>',
                  width: 20,
                  height: 20,
                ),
              )
              : HomeClock(
                enabled: !homeReducedMotion(context),
                builder:
                    (context, ms, child) => Transform.scale(
                      scale: HomeLoop.pulse(ms),
                      child: child,
                    ),
                child: ChunkyPressable(
                  depth: depth,
                  onTap: onTap,
                  semanticLabel: label,
                  builder:
                      (context, edge, pressed) => ChunkyBox(
                        fill: z.teal,
                        deep: z.tealDeep,
                        depth: edge,
                        radius: radius,
                        height: height,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  style: ZTypography.button.copyWith(
                                    fontSize: 25,
                                    height: 1,
                                    color: z.onTeal,
                                    shadows: [
                                      Shadow(
                                        color: z.tealDeep,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ChunkyBox(
                              fill: z.surface,
                              circle: true,
                              depth: 0,
                              highlight: false,
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              child: SvgPicture.string(
                                '<svg viewBox="0 0 20 22"><path d="M16 3L4 11l12 8z" fill="${svgHex(z.teal)}" stroke="${svgHex(zs.outline)}" stroke-width="2.6" stroke-linejoin="round"/></svg>',
                                width: 18,
                                height: 20,
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
