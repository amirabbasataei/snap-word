import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';

/// Below this width the date chip leaves the header row (the amber ribbon
/// would shrink to unreadable text) and sits under it.
const _wideHeader = 360.0;

/// Top of the daily screens (canvas `ZDailyBeforeA` / `ZDailyAfterA`): the
/// 44dp back button, the compact amber swallow-tail ribbon and — before the
/// game — the date chip at the end. [dateLabel] null keeps the end empty, so
/// the ribbon stays centred.
class DailyHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final String? dateLabel;

  const DailyHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: LayoutBuilder(
        builder: (context, c) {
          final label = dateLabel;
          final inRow = label != null && c.maxWidth >= _wideHeader - 28;
          return Column(
            children: [
              Row(
                children: [
                  ZGameBackButton(onTap: onBack),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Center(
                      child: ZRibbonTitle(
                        title,
                        accent: ZDialogAccent.amber,
                        expand: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (inRow)
                    DailyDateChip(label)
                  else
                    const SizedBox(width: ZGame.gameBackButton),
                ],
              ),
              if (label != null && !inRow)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: DailyPill(label),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The date at the end of the header: a 36dp surface chip with a 3dp edge.
class DailyDateChip extends StatelessWidget {
  final String label;

  const DailyDateChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ChunkyBox(
        fill: z.surface,
        depth: ZGame.depthSm,
        radius: 12,
        highlight: false,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          style: ZTypography.button.copyWith(
            fontSize: 12.5,
            height: 1,
            color: z.ink,
          ),
        ),
      ),
    );
  }
}

/// A small outlined surface pill with one line of text, scaled down rather
/// than wrapped when the screen is narrow.
class DailyPill extends StatelessWidget {
  final String text;

  const DailyPill(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ZChunkPill(
            fill: z.surface,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              maxLines: 1,
              style: ZTypography.metaLabel.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1,
                color: z.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
