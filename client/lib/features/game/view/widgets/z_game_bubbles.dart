import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
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

/// A premium taunt shown inside the chain (canvas `ZVersusA`): an amber pill
/// next to the sender's disc, in the chain flow right under the sender's last
/// word. It stays in the chain only while [visible]; the screen hides it after
/// a few seconds (the game state keeps just the latest taunt).
class ZChainTaunt {
  final String text;

  /// Sent by the local player (start side) rather than the opponent.
  final bool mine;

  /// Chain index of the word the taunt sits under; -1 puts it right after the
  /// start chip. When the sender has no word yet it goes under the newest word
  /// (see [zTauntAnchor]).
  final int afterIndex;
  final bool visible;

  const ZChainTaunt({
    required this.text,
    required this.mine,
    required this.afterIndex,
    this.visible = true,
  });
}

/// Where a taunt from [mine]'s side goes: under that player's most recent
/// word. A taunt sent before its sender has played anything (game start, or a
/// player who is still waiting) has no word to follow, so it sits at the end of
/// the chain — under whatever was played last, or right after the start chip
/// when the chain is empty — where the eye already is.
int zTauntAnchor(List<ZBubbleEntry> entries, {required bool mine}) {
  final i = entries.lastIndexWhere((e) => e.mine == mine);
  return i >= 0 ? i : entries.length - 1;
}

/// Maps a head-to-head game's shared chain to bubbles; [isMine] says whether
/// the word at chain index `i` is the local player's. `wordScores` only ever
/// accumulates the player's own words (see `GameBloc`) — it isn't parallel to
/// `wordChain` once the opponent's interspersed words are counted, so a
/// "mine" bubble looks its points up by move count, not by chain index.
List<ZBubbleEntry> zBubbleEntries(
  GameActive state, {
  required bool Function(int i) isMine,
}) {
  final entries = <ZBubbleEntry>[];
  var myMove = 0;
  for (var i = 0; i < state.wordChain.length; i++) {
    final mine = isMine(i);
    int? points;
    if (mine && myMove < state.wordScores.length) {
      points = state.wordScores[myMove];
    }
    if (mine) myMove++;
    entries.add(
      ZBubbleEntry(word: state.wordChain[i], mine: mine, points: points),
    );
  }
  return entries;
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

  /// Replace the default discs (my initial / the robot) — a duel passes the
  /// players' own, with their premium avatars.
  final Widget Function(double size)? myAvatar;
  final Widget Function(double size)? opponentAvatar;

  /// The latest taunt, rendered inline after word [ZChainTaunt.afterIndex].
  final ZChainTaunt? taunt;

  const ZBubbleChain({
    super.key,
    required this.entries,
    required this.nextStartLetter,
    required this.myTurn,
    required this.myInitial,
    this.startLabel = 'شروع زنجیر',
    this.myAvatar,
    this.opponentAvatar,
    this.taunt,
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
    final taunt = widget.taunt;
    Widget tauntRow(ZChainTaunt t) => _TauntRow(
      key: const ValueKey('chain-taunt'),
      taunt: t,
      myInitial: widget.myInitial,
      myAvatar: widget.myAvatar,
      opponentAvatar: widget.opponentAvatar,
    );
    return ZChainScroller(
      // A taunt appearing scrolls the chain down like a new word does.
      itemCount: entries.length + (taunt != null && taunt.visible ? 1 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _StartChip(label: widget.startLabel)),
          if (taunt != null && taunt.afterIndex < 0) tauntRow(taunt),
          for (var i = 0; i < entries.length; i++) ...[
            const SizedBox(height: 12),
            _BubbleRow(
              key: ValueKey(i),
              index: i,
              entry: entries[i],
              isLast: i == lastIndex,
              animateIn: i >= _initialLength,
              myInitial: widget.myInitial,
              myAvatar: widget.myAvatar,
              opponentAvatar: widget.opponentAvatar,
            ),
            if (taunt != null && taunt.afterIndex == i) tauntRow(taunt),
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

/// The in-chain taunt: sender's disc + amber pill, on the sender's side. It
/// collapses (rather than vanishing) when hidden so the words below don't jump.
class _TauntRow extends StatelessWidget {
  final ZChainTaunt taunt;
  final String myInitial;
  final Widget Function(double size)? myAvatar;
  final Widget Function(double size)? opponentAvatar;

  const _TauntRow({
    super.key,
    required this.taunt,
    required this.myInitial,
    this.myAvatar,
    this.opponentAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final mine = taunt.mine;
    final still = homeReducedMotion(context);
    final disc =
        mine
            ? (myAvatar?.call(ZGame.gameBubbleAvatar) ??
                ZDiscAvatar.me(
                  context,
                  letter: myInitial,
                  size: ZGame.gameBubbleAvatar,
                  highlight: false,
                ))
            : (opponentAvatar?.call(ZGame.gameBubbleAvatar) ??
                ZDiscAvatar.robot(
                  context,
                  size: ZGame.gameBubbleAvatar,
                  highlight: false,
                ));
    final pill = Flexible(
      child: ChunkyBox(
        fill: z.amber,
        depth: ZGame.depthSm,
        radius: 19,
        highlight: false,
        borderWidth: ZGame.outlineInner,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 14, color: z.onAmber),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                taunt.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: z.onAmber,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mine) ...[
          disc,
          const SizedBox(width: 8),
          pill,
        ] else ...[
          pill,
          const SizedBox(width: 8),
          disc,
        ],
      ],
    );
    return AnimatedSize(
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child:
          taunt.visible
              ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment:
                      mine
                          ? AlignmentDirectional.centerStart
                          : AlignmentDirectional.centerEnd,
                  child: Semantics(
                    liveRegion: true,
                    label: '${mine ? 'تو' : 'حریف'}: ${taunt.text}',
                    excludeSemantics: true,
                    child: ZDropIn(animate: true, child: row),
                  ),
                ),
              )
              : const SizedBox(width: double.infinity),
    );
  }
}

class _StartChip extends StatelessWidget {
  final String label;

  const _StartChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZChunkPill(
      fill: z.surface,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: TextStyle(
          color: z.ink,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          height: 1,
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
  final Widget Function(double size)? myAvatar;
  final Widget Function(double size)? opponentAvatar;

  const _BubbleRow({
    super.key,
    required this.index,
    required this.entry,
    required this.isLast,
    required this.animateIn,
    required this.myInitial,
    this.myAvatar,
    this.opponentAvatar,
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
            ? (myAvatar?.call(ZGame.gameBubbleAvatar) ??
                ZDiscAvatar.me(
                  context,
                  letter: myInitial,
                  size: ZGame.gameBubbleAvatar,
                  highlight: false,
                ))
            : (opponentAvatar?.call(ZGame.gameBubbleAvatar) ??
                ZDiscAvatar.robot(
                  context,
                  size: ZGame.gameBubbleAvatar,
                  highlight: false,
                ));

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
