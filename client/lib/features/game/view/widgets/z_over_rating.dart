import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/game/bloc/game_state.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// What a 1v1 result says about the player's «جام» (rating). No canvas frame
/// exists for it (the canvas predates the rating); built from the ZOver tokens
/// like the other cards of the screen.
///
/// * the server's `rating_update` arrived → the signed change in a teal /
///   coral chip beside the new total («+۱۶ · جام تو ۱٬۰۱۶»);
/// * the same, but `pair_cap` → nothing moved: a neutral «۰» chip and why;
/// * the opponent was the AI fallback → a one-line note, no number;
/// * otherwise nothing (the update may still be on its way — it follows
///   `game_over` by a database write — or the game was a draw).
class ZOverRatingCard extends StatelessWidget {
  final GameOver state;

  const ZOverRatingCard({super.key, required this.state});

  static const aiNote = 'بازی با هوش مصنوعی جام نداره';
  static String pairCapNote =
      'امروز ${toPersianDigits(GameConstants.ratingPairCapPerDay)} بار با این '
      'حریف بازی کردی. بازی‌های بعدیِ امروز جام نداره.';

  /// Whether the card has anything to show for [state].
  static bool shows(GameOver state) =>
      state.rating != null || state.opponentIsAi;

  @override
  Widget build(BuildContext context) {
    final rating = state.rating;
    if (rating != null) return _Delta(state: state);
    if (state.opponentIsAi) return const _Note(aiNote);
    return const SizedBox.shrink();
  }
}

class _Delta extends StatelessWidget {
  final GameOver state;

  const _Delta({required this.state});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final r = state.rating!;
    final capped = state.ratingPairCap;
    final (fill, deep, on) =
        capped || r.delta == 0
            ? (z.wash, context.zs.tileDeep, z.ink)
            : r.delta > 0
            ? (z.teal, z.tealDeep, z.onTeal)
            : (z.coral, z.coralDeep, z.onCoral);
    final change = formatSignedPersianNumber(r.delta);
    final total = formatPersianNumber(r.after);
    final summary =
        capped
            ? 'جامت همونه، ${toPersianDigits(r.after)}'
            : r.delta == 0
            ? 'جامت عوض نشد، $total'
            : r.delta > 0
            ? 'جامت ${toPersianDigits(r.delta)} تا بیشتر شد و شد $total'
            : 'جامت ${toPersianDigits(r.delta.abs())} تا کم شد و شد $total';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: capped ? '$summary. ${ZOverRatingCard.pairCapNote}' : summary,
      child: ChunkyBox(
        fill: z.surface,
        depth: 4,
        radius: 16,
        highlight: false,
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ChunkyBox(
                  fill: fill,
                  deep: deep,
                  depth: 3,
                  radius: 12,
                  highlight: !capped && r.delta != 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  alignment: Alignment.center,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      change,
                      style: TextStyle(
                        color: on,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'جام تو',
                        style: TextStyle(
                          color: z.ink60,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          total,
                          style: TextStyle(
                            color: z.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!capped && r.delta != 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    'قبلاً ${formatPersianNumber(r.before)}',
                    style: TextStyle(
                      color: z.ink60,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            if (capped) ...[
              const SizedBox(height: 8),
              Text(
                ZOverRatingCard.pairCapNote,
                style: TextStyle(
                  color: z.ink60,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: z.wash,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: z.ink60,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
