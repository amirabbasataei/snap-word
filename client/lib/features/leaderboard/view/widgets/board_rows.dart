import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_parts.dart';

/// The ranked list under the podium (canvas `ZBoardA`): a surface plate whose
/// top edge butts against the pedestals when there is a podium, with a rank
/// bead, avatar, name, an optional sub-line and the score on every row. The
/// player's own row is tinted.
class BoardRowsCard extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final String currentUserId;

  /// A podium sits above — square the top corners to meet it.
  final bool underPodium;

  const BoardRowsCard({
    super.key,
    required this.entries,
    required this.currentUserId,
    required this.underPodium,
  });

  @override
  Widget build(BuildContext context) {
    final top = underPodium ? Radius.zero : const Radius.circular(20);
    return ChunkyBox(
      fill: context.z.surface,
      depth: 4,
      highlight: false,
      borderRadius: BorderRadiusDirectional.only(
        topStart: top,
        topEnd: top,
        bottomStart: const Radius.circular(20),
        bottomEnd: const Radius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            BoardRow(
              entry: entries[i],
              index: i,
              divider: i > 0,
              mine: entries[i].userId == currentUserId,
            ),
        ],
      ),
    );
  }
}

class BoardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final int index;
  final bool divider;
  final bool mine;

  const BoardRow({
    super.key,
    required this.entry,
    required this.index,
    required this.divider,
    required this.mine,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final chain = entry.chainLength;
    final sub = chain == null ? null : 'زنجیر ${toPersianDigits(chain)} کلمه';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'رتبهٔ ${toPersianDigits(entry.rank)}: ${isolate(entry.username)}'
          '${sub == null ? '' : '، $sub'}، '
          '${formatPersianNumber(entry.score)} امتیاز${mine ? '، تو' : ''}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: mine ? z.tintIndigo : null,
          borderRadius: mine ? BorderRadius.circular(12) : null,
          border:
              divider && !mine
                  ? Border(top: BorderSide(color: z.wash, width: 2))
                  : null,
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: z.wash, shape: BoxShape.circle),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    toPersianDigits(entry.rank),
                    style: ZTypography.button.copyWith(
                      fontSize: 13,
                      color: z.ink,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            BoardDisc(
              name: entry.username,
              index: index,
              size: 36,
              avatarId: entry.avatarId,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZTypography.button.copyWith(
                      fontSize: 14,
                      height: 1.3,
                      color: z.ink,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZTypography.metaLabel.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: z.ink60,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatPersianNumber(entry.score),
              style: ZTypography.button.copyWith(fontSize: 15, color: z.ink),
            ),
          ],
        ),
      ),
    );
  }
}
