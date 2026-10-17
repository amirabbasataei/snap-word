import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// One opponent level in the picker.
class AiLevel {
  /// The `opponentType` the game route takes.
  final String id;
  final String title;

  /// The character's name — decorative, the canvas's flavour text.
  final String name;
  final ZDialogAccent accent;

  /// Speed bars filled (1–3). The canvas draws bars only, no seconds.
  final int speed;

  const AiLevel({
    required this.id,
    required this.title,
    required this.name,
    required this.accent,
    required this.speed,
  });
}

/// Canvas turn 7 frame 7p, "حریف هوشمند — انتخاب سطح". Titles are the real
/// levels; the character names are flavour.
const aiLevels = [
  AiLevel(
    id: 'ai_easy',
    title: 'آسان',
    name: 'خواب‌آلود',
    accent: ZDialogAccent.teal,
    speed: 1,
  ),
  AiLevel(
    id: 'ai_medium',
    title: 'متوسط',
    name: 'هوشیار',
    accent: ZDialogAccent.amber,
    speed: 2,
  ),
  AiLevel(
    id: 'ai_hard',
    title: 'سخت',
    name: 'بدقلق',
    accent: ZDialogAccent.coral,
    speed: 3,
  ),
];

/// The preselected level.
const aiDefaultLevel = 'ai_medium';

/// Asks which vs-AI level to play. Resolves to the chosen `opponentType`, or
/// null when the player closes the dialog without starting.
Future<String?> showAiLevelDialog(BuildContext context) =>
    showZDialog<String>(
      context,
      barrierLabel: 'بستن',
      builder: (dialogContext) => AiLevelDialog(
        onStart: (id) => Navigator.of(dialogContext).pop(id),
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );

class AiLevelDialog extends StatefulWidget {
  final ValueChanged<String> onStart;
  final VoidCallback onClose;

  const AiLevelDialog({super.key, required this.onStart, required this.onClose});

  @override
  State<AiLevelDialog> createState() => _AiLevelDialogState();
}

class _AiLevelDialogState extends State<AiLevelDialog> {
  String _selected = aiDefaultLevel;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZDialogCard(
      semanticLabel: 'سطح حریف را انتخاب کن',
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سطح حریف را انتخاب کن',
                      style: ZTypography.screenTitle.copyWith(
                        fontSize: 20,
                        height: 1.25,
                        color: z.ink,
                      ),
                    ),
                    Text(
                      // Canvas: «… و بددهن‌تر» — the AI never speaks, so the
                      // line names what really changes between levels.
                      'هرچه سخت‌تر، سریع‌تر و کم‌اشتباه‌تر',
                      style: ZTypography.body.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                        color: z.ink60,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CloseButton(onTap: widget.onClose),
            ],
          ),
          const SizedBox(height: 12),
          for (final level in aiLevels) ...[
            _LevelCard(
              level: level,
              selected: level.id == _selected,
              onTap: () => setState(() => _selected = level.id),
            ),
            const SizedBox(height: 12),
          ],
          ZDialogButton.primary(
            label: 'شروع بازی',
            accent: ZDialogAccent.indigo,
            height: 56,
            radius: 18,
            depth: ZGame.depthSm + 1,
            fontSize: 17,
            onTap: () => widget.onStart(_selected),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      button: true,
      label: 'بستن',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ChunkyBox(
          fill: z.wash,
          depth: 0,
          highlight: false,
          radius: 14,
          borderWidth: ZGame.outlineInner,
          width: ZGame.hudIconButton,
          height: ZGame.hudIconButton,
          alignment: Alignment.center,
          child: SvgPicture.string(
            '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.ink)}" stroke-width="3" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
            width: 16,
            height: 16,
          ),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final AiLevel level;
  final bool selected;
  final VoidCallback onTap;

  const _LevelCard({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (accent, deep) = switch (level.accent) {
      ZDialogAccent.teal => (z.teal, z.tealDeep),
      ZDialogAccent.amber => (z.amber, z.amberDeep),
      ZDialogAccent.coral => (z.coral, z.coralDeep),
      ZDialogAccent.indigo => (z.indigo, z.indigoDeep),
    };
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '${level.title}، ${level.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Selected: paper face lifted on the accent's edge; otherwise a flat
        // card with a 3px outline edge (canvas `card` styles).
        child: Padding(
          padding: EdgeInsets.only(bottom: selected ? 4 : 3),
          child: ChunkyBox(
            fill: selected ? z.paper : z.surface,
            deep: selected ? accent : null,
            depth: selected ? 4 : 3,
            radius: 20,
            highlight: false,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ChunkyBox(
                  fill: accent,
                  depth: 0,
                  radius: 16,
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  child: _RobotFace(level: level),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            level.title,
                            style: ZTypography.button.copyWith(
                              fontSize: 16,
                              height: 1.3,
                              color: z.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            level.name,
                            style: ZTypography.button.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              color: z.ink60,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            'سرعت',
                            style: ZTypography.metaLabel.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: z.ink60,
                            ),
                          ),
                          const SizedBox(width: 6),
                          for (var i = 1; i <= 3; i++) ...[
                            if (i > 1) const SizedBox(width: 3),
                            Container(
                              width: 14,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i <= level.speed ? accent : z.wash,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: context.zs.outline,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _Radio(on: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool on;

  const _Radio({required this.on});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? z.indigo : z.surface,
        shape: BoxShape.circle,
        border: Border.all(color: context.zs.outline, width: ZGame.outline),
      ),
      child:
          on
              ? SvgPicture.string(
                '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.onIndigo)}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7"/></svg>',
                width: 14,
                height: 14,
              )
              : null,
    );
  }
}

/// The level's robot face: sleepy lines (easy), round eyes (medium), round
/// eyes under angry brows (hard), and a mouth that goes from a smile to a
/// scowl.
class _RobotFace extends StatelessWidget {
  final AiLevel level;

  const _RobotFace({required this.level});

  @override
  Widget build(BuildContext context) {
    final o = svgHex(context.zs.outline);
    final surface = svgHex(context.z.surface);
    final easy = level.id == 'ai_easy';
    final hard = level.id == 'ai_hard';
    final mouth = switch (level.id) {
      'ai_easy' => 'M16 28q5 4 10 0',
      'ai_hard' => 'M16 30q5 -4 10 0',
      _ => 'M16 28h10',
    };
    final eyes =
        easy
            ? '<path d="M12 21h6M24 21h6" stroke="$o" stroke-width="3.5" stroke-linecap="round"/>'
            : '<circle cx="15" cy="21" r="3.5" fill="$o"/><circle cx="27" cy="21" r="3.5" fill="$o"/>';
    final brows =
        hard
            ? '<path d="M11 14l7 3M31 14l-7 3" stroke="$o" stroke-width="3.5" stroke-linecap="round"/>'
            : '';
    return SvgPicture.string(
      '<svg viewBox="0 0 42 40"><rect x="6" y="8" width="30" height="26" rx="8" fill="$surface" stroke="$o" stroke-width="3.5"/>$eyes$brows<path d="$mouth" fill="none" stroke="$o" stroke-width="3.5" stroke-linecap="round"/></svg>',
      width: 34,
      height: 32,
    );
  }
}
