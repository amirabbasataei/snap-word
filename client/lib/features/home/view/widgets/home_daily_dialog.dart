import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/link_position.dart';
import 'package:wordchain/features/game/view/widgets/z_game_word.dart';
import 'package:wordchain/features/home/view/widgets/home_level_dialog.dart';

/// One Daily Challenge variant in the type picker.
class DailyTypeOption {
  /// The letter position that links words (`GameConstants.dailyVariants`).
  final int variant;

  /// «کلاسیک» / «سخت» / «خیلی سخت».
  final String level;
  final ZDialogAccent accent;

  /// Two dictionary words that link under this variant's rule, shown with
  /// their linking letters coloured like in the game.
  final (String, String) example;

  const DailyTypeOption({
    required this.variant,
    required this.level,
    required this.accent,
    required this.example,
  });
}

/// The three Daily Challenge types. The harder examples are the ones of the
/// feature request (باران → انتظار links on the 2nd letter, باران → بانی on
/// the 3rd).
const dailyTypeOptions = [
  DailyTypeOption(
    variant: 1,
    level: 'کلاسیک',
    accent: ZDialogAccent.teal,
    example: ('باران', 'نارنج'),
  ),
  DailyTypeOption(
    variant: 2,
    level: 'سخت',
    accent: ZDialogAccent.amber,
    example: ('باران', 'انتظار'),
  ),
  DailyTypeOption(
    variant: 3,
    level: 'خیلی سخت',
    accent: ZDialogAccent.coral,
    example: ('باران', 'بانی'),
  ),
];

/// Asks which Daily Challenge type to play (Home's «چالش روزانه» button).
/// Like the vs-AI level picker but with no start button: tapping a type
/// chooses it. [played] are the variants already played today (marked ✓;
/// still selectable, the result screen opens). Resolves to the variant, or
/// null when the dialog is closed.
Future<int?> showDailyTypeDialog(
  BuildContext context, {
  List<int> played = const [],
}) => showZDialog<int>(
  context,
  barrierLabel: 'بستن',
  builder:
      (dialogContext) => DailyTypeDialog(
        played: played,
        onSelect: (v) => Navigator.of(dialogContext).pop(v),
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
);

class DailyTypeDialog extends StatelessWidget {
  final List<int> played;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  const DailyTypeDialog({
    super.key,
    this.played = const [],
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZDialogCard(
      semanticLabel: 'نوع چالش رو انتخاب کن',
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
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
                      'نوع چالش رو انتخاب کن',
                      style: ZTypography.screenTitle.copyWith(
                        fontSize: 20,
                        height: 1.25,
                        color: z.ink,
                      ),
                    ),
                    Text(
                      'هر نوع جدول و جایزهٔ خودش رو داره',
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
              HomeDialogCloseButton(onTap: onClose),
            ],
          ),
          const SizedBox(height: 12),
          for (final option in dailyTypeOptions) ...[
            _TypeCard(
              option: option,
              played: played.contains(option.variant),
              onTap: () => onSelect(option.variant),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final DailyTypeOption option;
  final bool played;
  final VoidCallback onTap;

  const _TypeCard({
    required this.option,
    required this.played,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (accent, deep) = switch (option.accent) {
      ZDialogAccent.teal => (z.teal, z.tealDeep),
      ZDialogAccent.amber => (z.amber, z.amberDeep),
      ZDialogAccent.coral => (z.coral, z.coralDeep),
      ZDialogAccent.indigo => (z.indigo, z.indigoDeep),
    };
    final variant = option.variant;
    final seconds = toPersianDigits(GameConstants.dailyTurnTimerSec(variant));
    final rule =
        variant == 1
            ? 'کلمه با حرف آخر قبلی شروع بشه'
            : 'حرف ${linkOrdinal(variant)} = حرف آخر قبلی';
    return ChunkyPressable(
      depth: 4,
      onTap: onTap,
      semanticLabel:
          '${linkVariantName(variant)}، ${option.level}، $rule، $seconds ثانیه'
          '${played ? '، امروز بازی کردی' : ''}',
      builder:
          (context, depth, pressed) => ExcludeSemantics(
            child: ChunkyBox(
              fill: z.surface,
              deep: deep,
              depth: depth,
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
                    child: _PositionGlyph(position: variant),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              linkVariantName(variant),
                              style: ZTypography.button.copyWith(
                                fontSize: 16,
                                height: 1.3,
                                color: z.ink,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${option.level} · $seconds ثانیه',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZTypography.button.copyWith(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                  color: z.ink60,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                zChainWordSpan(
                                  context,
                                  word: option.example.$1,
                                  index: 0,
                                  fontSize: 14,
                                  color: z.ink,
                                  linkPosition: variant,
                                ),
                                TextSpan(
                                  text: '  ←  ',
                                  style: TextStyle(
                                    color: z.ink40,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                zChainWordSpan(
                                  context,
                                  word: option.example.$2,
                                  index: 1,
                                  fontSize: 14,
                                  color: z.ink,
                                  linkPosition: variant,
                                ),
                              ],
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (played) ...[
                    const SizedBox(width: 8),
                    _PlayedMark(),
                  ] else
                    _Chevron(color: z.ink40),
                ],
              ),
            ),
          ),
    );
  }
}

/// Three letter cells (the first at the start of the line) with the linking
/// one solid: which letter of the word the chain hangs on.
class _PositionGlyph extends StatelessWidget {
  final int position;

  const _PositionGlyph({required this.position});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final outline = context.zs.outline;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 3; i++) ...[
              if (i > 1) const SizedBox(width: 3),
              Container(
                width: 11,
                height: 14,
                decoration: BoxDecoration(
                  color: i == position ? z.surface : null,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: outline, width: 2),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          toPersianDigits(position),
          style: TextStyle(
            color: outline,
            fontWeight: FontWeight.w900,
            fontSize: 13,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _PlayedMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: z.tintTeal,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.zs.outline, width: 2),
      ),
      child: Text(
        'بازی کردی ✓',
        style: TextStyle(
          color: context.zs.tealInk,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          height: 1,
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  final Color color;

  const _Chevron({required this.color});

  @override
  Widget build(BuildContext context) {
    // Points to the end of the line: left in RTL.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SvgPicture.string(
      '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(color)}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="${rtl ? 'M15 6l-6 6 6 6' : 'M9 6l6 6-6 6'}"/></svg>',
      width: 18,
      height: 18,
    );
  }
}
