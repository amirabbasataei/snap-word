import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_parts.dart';

/// The top three on pedestals (canvas `ZBoardA`): 2nd on the start side, 1st
/// in the middle under a crown, 3rd on the end side. Heights are minimums, so
/// large text grows a block instead of overflowing it.
class BoardPodium extends StatelessWidget {
  /// Rank-ascending: index 0 is رتبهٔ ۱.
  final List<LeaderboardEntry> top3;
  final String currentUserId;

  const BoardPodium({
    super.key,
    required this.top3,
    required this.currentUserId,
  }) : assert(top3.length == 3);

  @override
  Widget build(BuildContext context) {
    Widget cell(int place, {required int flex}) => Expanded(
      flex: flex,
      child: _Pedestal(
        entry: top3[place - 1],
        place: place,
        mine: top3[place - 1].userId == currentUserId,
      ),
    );
    // Flex 10 : 11 : 10 — the canvas's 1 : 1.1 : 1.
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          cell(2, flex: 10),
          const SizedBox(width: 6),
          cell(1, flex: 11),
          const SizedBox(width: 6),
          cell(3, flex: 10),
        ],
      ),
    );
  }
}

class _Pedestal extends StatelessWidget {
  final LeaderboardEntry entry;
  final int place;
  final bool mine;

  const _Pedestal({
    required this.entry,
    required this.place,
    required this.mine,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final first = place == 1;
    final disc = first ? 66.0 : 56.0;
    final (discFill, onDisc) = switch (place) {
      1 => (z.indigo, z.onIndigo),
      2 => (z.coral, z.onCoral),
      _ => (z.teal, z.onTeal),
    };
    final (blockFill, onBlock, scoreColor, rankColor) = switch (place) {
      1 => (z.amber, z.onAmber, z.onAmber, z.onAmber),
      2 => (z.indigo, z.onIndigo, z.onIndigo, z.onIndigo),
      _ => (z.surface, z.ink, z.ink60, zs.tealInk),
    };
    final minHeight = switch (place) {
      1 => 124.0,
      2 => 96.0,
      _ => 76.0,
    };
    final rankSize = switch (place) {
      1 => 38.0,
      2 => 30.0,
      _ => 26.0,
    };

    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        ExcludeSemantics(
          child: ZDiscAvatar(
            fill: discFill,
            onFill: onDisc,
            letter: avatarInitial(entry.username, fallback: '؟'),
            size: disc,
            avatarId: entry.avatarId,
          ),
        ),
        if (mine)
          PositionedDirectional(
            top: -6,
            end: -12,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: ZChunkPill(
                fill: z.indigo,
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  'تو',
                  style: ZTypography.button.copyWith(
                    fontSize: 11,
                    color: z.onIndigo,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'رتبهٔ ${toPersianDigits(place)}: ${isolate(entry.username)}، '
          '${formatPersianNumber(entry.score)} امتیاز${mine ? '، تو' : ''}',
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (first)
              // The crown overlaps the disc by 12 (canvas margin-bottom -12).
              Stack(
                clipBehavior: Clip.none,
                alignment: AlignmentDirectional.topCenter,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: avatar,
                  ),
                  ExcludeSemantics(
                    child: SvgPicture.string(
                      '<svg viewBox="0 0 22 16"><path d="M2 14L1 3l5.5 4L11 1l4.5 6L21 3l-1 11z" fill="${svgHex(z.amber)}" stroke="${svgHex(zs.outline)}" stroke-width="2" stroke-linejoin="round"/></svg>',
                      width: 40,
                      height: 26,
                    ),
                  ),
                ],
              )
            else
              avatar,
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: minHeight,
                minWidth: double.infinity,
              ),
              child: ChunkyBox(
                fill: blockFill,
                depth: 4,
                highlight: place != 3,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(14),
                  topEnd: Radius.circular(14),
                  bottomStart: Radius.circular(4),
                  bottomEnd: Radius.circular(4),
                ),
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          toPersianDigits(place),
                          style: ZTypography.display.copyWith(
                            fontSize: rankSize,
                            color: rankColor,
                          ),
                        ),
                      ),
                      Text(
                        entry.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: ZTypography.button.copyWith(
                          fontSize: first ? 14 : 13,
                          height: 1.4,
                          color: onBlock,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatPersianNumber(entry.score),
                          style: ZTypography.cardTitle.copyWith(
                            fontSize: first ? 12.5 : 12,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            color: scoreColor,
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
      ),
    );
  }
}
