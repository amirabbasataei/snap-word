import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

/// «جام» — the Elo rating from `GET /profile/stats` (`rating`, `peak_rating`,
/// `rated_games`) as a big indigo tile, with the best rating and the rated
/// games beside it. (The lifetime word points, `total_score`, are not shown:
/// they are nearly the same number as the experience on the level bar.)
/// Not in the canvas (it predates the rating); laid out like the stat grid
/// under it. Signed-in players only — a guest has no rating.
class ProfileRatingCard extends StatelessWidget {
  final ProfileStats stats;

  const ProfileRatingCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final rating = formatPersianNumber(stats.rating);
    final unrated = stats.ratedGames == 0;
    final rows = [
      ('بیشترین جام', formatPersianNumber(stats.peakRating)),
      ('بازی با جام', formatPersianNumber(stats.ratedGames)),
    ];
    final small = ZTypography.button.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      height: 1.4,
      color: z.onIndigo,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 125,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label:
                    'جام تو: $rating'
                    '${unrated ? '. هنوز بازی آنلاین نکردی' : ''}',
                child: ChunkyBox(
                  fill: z.indigo,
                  deep: z.indigoDeep,
                  depth: ZGame.depthMd,
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('جام تو', style: small),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          rating,
                          maxLines: 1,
                          style: ZTypography.display.copyWith(
                            fontSize: 44,
                            color: z.onIndigo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 200,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ChunkyBox(
                fill: z.surface,
                depth: 4,
                radius: 16,
                highlight: false,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (label, value) in rows)
                      Semantics(
                        container: true,
                        excludeSemantics: true,
                        label: '$label: $value',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZTypography.body.copyWith(
                                    fontSize: 12,
                                    height: 1.4,
                                    fontWeight: FontWeight.w700,
                                    color: z.ink60,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                value,
                                maxLines: 1,
                                style: ZTypography.button.copyWith(
                                  fontSize: 15,
                                  height: 1.3,
                                  color: z.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
