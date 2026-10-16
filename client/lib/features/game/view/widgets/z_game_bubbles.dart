import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/game/view/widgets/z_game_chain.dart';
import 'package:wordchain/features/game/view/widgets/z_game_scroll.dart';
import 'package:wordchain/features/game/view/widgets/z_game_word.dart';

/// One word of a shared two-player chain.
class ZBubbleEntry {
  final String word;

  /// Played by the local player (start side, with a points pill) rather than
  /// the opponent (end side).
  final bool mine;

  /// Points this word scored; only the local player's words carry them.
  final int? points;

  const ZBubbleEntry({required this.word, required this.mine, this.points});
}

/// The head-to-head chain of ZPlay (canvas `ZPlayA`): chat-style chunky
/// bubbles — yours on the start side (indigo disc, indigo depth edge, points
/// pill), the opponent's on the end side (robot disc, surface bubble) — with a
/// tail corner next to the disc and the shared letters in the chain's accent
/// cycle. The newest bubble is larger and drops in; a dashed slot says what
/// the next word starts with. Bottom-anchored and scrollable like the spine.
///
/// Convention for the head-to-head screens (ZVersus follows it): *me* on the
/// start side, *them* on the end side.
class ZBubbleChain extends StatefulWidget {
  final List<ZBubbleEntry> entries;
  final String? nextStartLetter;

  /// Whose turn the dashed slot belongs to (which side it sits on).
  final bool myTurn;
  final String myInitial;
  final String startLabel;

  const ZBubbleChain({
    super.key,
    required this.entries,
    required this.nextStartLetter,
    required this.myTurn,
    required this.myInitial,
    this.startLabel = 'شروع زنجیر',
  });

  @override
  State<ZBubbleChain> createState() => _ZBubbleChainState();
}

class _ZBubbleChainState extends State<ZBubbleChain> {
  /// Words present when the screen opened (a resumed game) don't drop in.
  late final int _initialLength = widget.entries.length;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final lastIndex = entries.length - 1;
    return ZChainScroller(
      itemCount: entries.length,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _StartChip(label: widget.startLabel)),
          for (var i = 0; i < entries.length; i++) ...[
            const SizedBox(height: 12),
            _BubbleRow(
              key: ValueKey(i),
              index: i,
              entry: entries[i],
              isLast: i == lastIndex,
              animateIn: i >= _initialLength,
              myInitial: widget.myInitial,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment:
                widget.myTurn
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
            child: ZNextLetterSlot(letter: widget.nextStartLetter),
          ),
        ],
      ),
    );
  }
}

class _StartChip extends StatelessWidget {
  final String label;

  const _StartChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      depth: 0,
      radius: 999,
      highlight: false,
      borderWidth: ZGame.outlineInner,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // Not `alignment:` — that would stretch the chip across the chain.
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: TextStyle(
            color: z.ink,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _BubbleRow extends StatelessWidget {
  final int index;
  final ZBubbleEntry entry;
  final bool isLast;
  final bool animateIn;
  final String myInitial;

  const _BubbleRow({
    super.key,
    required this.index,
    required this.entry,
    required this.isLast,
    required this.animateIn,
    required this.myInitial,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final mine = entry.mine;
    const tail = Radius.circular(ZGame.gameBubbleTail);
    const round = Radius.circular(18);

    final bubble = ChunkyBox(
      fill: mine ? zs.tile : z.surface,
      deep: mine ? z.indigo : zs.tileDeep,
      depth: ZGame.depthMd - 1,
      highlight: mine,
      // The flat corner sits next to the disc.
      borderRadius:
          mine
              ? const BorderRadiusDirectional.only(
                topStart: tail,
                topEnd: round,
                bottomStart: round,
                bottomEnd: round,
              )
              : const BorderRadiusDirectional.only(
                topStart: round,
                topEnd: tail,
                bottomStart: round,
                bottomEnd: round,
              ),
      height: isLast ? ZGame.gameBubbleLast : ZGame.gameBubble,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      // Not `alignment:` — that would stretch the bubble across the row.
      child: Center(
        widthFactor: 1,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            zChainWordSpan(
              context,
              word: entry.word,
              index: index,
              fontSize: isLast ? 25 : 22,
              color: z.ink,
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    );

    final disc =
        mine
            ? ZDiscAvatar.me(
              context,
              letter: myInitial,
              size: ZGame.gameBubbleAvatar,
              highlight: false,
            )
            : ZDiscAvatar.robot(
              context,
              size: ZGame.gameBubbleAvatar,
              highlight: false,
            );

    final points = entry.points;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mine) ...[
          disc,
          const SizedBox(width: 8),
          Flexible(child: bubble),
          if (points != null) ...[
            const SizedBox(width: 8),
            ZPointsPill(points: points),
          ],
        ] else ...[
          Flexible(child: bubble),
          const SizedBox(width: 8),
          disc,
        ],
      ],
    );

    return Align(
      alignment:
          mine
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
      child: Semantics(
        label: entry.word,
        excludeSemantics: true,
        child: ZDropIn(animate: animateIn, child: row),
      ),
    );
  }
}
