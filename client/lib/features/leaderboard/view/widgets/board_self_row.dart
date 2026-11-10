import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_parts.dart';

/// «تو — name»: the player's own place, pinned under the list (canvas
/// `ZBoardA`: ink plate with an indigo edge). Whatever the rank is — in or out
/// of the loaded top 100, or none at all.
class BoardSelfRow extends StatelessWidget {
  final BoardTab tab;
  final String username;
  final String? avatarId;

  /// 0 = not ranked on this board.
  final int rank;

  /// Null = the server did not say.
  final int? score;
  final String subtitle;

  /// Show the score although the player has no rank yet — the rating is real
  /// before the tenth game, the weekly Δ is not (no rated game = no score).
  final bool showUnrankedScore;

  const BoardSelfRow({
    super.key,
    required this.tab,
    required this.username,
    required this.avatarId,
    required this.rank,
    required this.score,
    required this.subtitle,
    this.showUnrankedScore = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final ranked = rank > 0;
    final shownScore = ranked || showUnrankedScore ? score : null;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'تو — ${isolate(username)}. $subtitle'
          '${shownScore == null ? '' : '، ${boardScoreSpoken(tab, shownScore)}'}',
      child: ChunkyBox(
        fill: z.inkSurface,
        deep: z.indigo,
        depth: 5,
        radius: 18,
        highlight: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: z.indigo,
                shape: BoxShape.circle,
              ),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    ranked ? toPersianDigits(rank) : '—',
                    style: ZTypography.button.copyWith(
                      fontSize: 13,
                      color: z.onIndigo,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ExcludeSemantics(
              child: ZDiscAvatar.me(
                context,
                letter: avatarInitial(username, fallback: '؟'),
                size: 36,
                avatarId: avatarId,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تو — $username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZTypography.button.copyWith(
                      fontSize: 14,
                      height: 1.3,
                      color: z.onInkSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ZTypography.metaLabel.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: z.onInkSurfaceSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (shownScore != null) ...[
              const SizedBox(width: 8),
              BoardScoreText(
                tab: tab,
                score: shownScore,
                style: ZTypography.button.copyWith(
                  fontSize: 16,
                  color: z.onInkSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
