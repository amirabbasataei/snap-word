import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';

/// The stat tiles of the canvas: one big amber tile and three white ones.
///
/// Only what the stats really hold is drawn:
///  * big — «بلندترین زنجیر», `best_match_streak` (most words of one chain,
///    local max with the server's, see `ProfileCubit`);
///  * «بازی‌شده» — `total_matches`; «روز پیاپی» — `daily_streak`;
///  * wide — the longest word the player built, with its letter count.
/// The canvas's «برد آنلاین», «کلمهٔ درست ٪», «کلمهٔ یکتا» and the chain's
/// date have no field behind them and are not drawn.
class ProfileStatsGrid extends StatelessWidget {
  final ProfileStats stats;

  const ProfileStatsGrid({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final word = stats.longestWord;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 125,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _BigTile(
                label: 'بلندترین زنجیر',
                value: toPersianDigits(stats.bestMatchStreak),
                unit: 'کلمه',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Tile(
                          value: formatPersianNumber(stats.totalMatches),
                          label: 'بازی‌شده',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Tile(
                          value: formatPersianNumber(stats.dailyStreak),
                          label: 'روز پیاپی',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _WideTile(
                  value: word == null || word.isEmpty ? '—' : word,
                  label:
                      word == null || word.isEmpty
                          ? 'بلندترین کلمه'
                          : 'بلندترین کلمه · ${toPersianDigits(letterCount(word))} حرف',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _BigTile({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final small = ZTypography.button.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      height: 1.4,
      color: z.onAmber,
    );
    return Semantics(
      container: true,
      label: '$label: $value $unit',
      excludeSemantics: true,
      child: ChunkyBox(
        fill: z.amber,
        deep: z.amberDeep,
        depth: ZGame.depthMd,
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: small),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: ZTypography.display.copyWith(
                  fontSize: 50,
                  color: z.onAmber,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(unit, style: small),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String value;
  final String label;

  const _Tile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ChunkyBox(
          fill: z.surface,
          depth: 4,
          radius: 16,
          highlight: false,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  style: ZTypography.button.copyWith(
                    fontSize: 20,
                    height: 1.1,
                    color: z.ink,
                  ),
                ),
              ),
              Text(
                label,
                style: ZTypography.body.copyWith(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: z.ink60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideTile extends StatelessWidget {
  final String value;
  final String label;

  const _WideTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ChunkyBox(
          fill: z.surface,
          depth: 4,
          radius: 16,
          highlight: false,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZTypography.button.copyWith(
                  fontSize: 20,
                  height: 1.1,
                  color: z.ink,
                ),
              ),
              Text(
                label,
                style: ZTypography.body.copyWith(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: z.ink60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
