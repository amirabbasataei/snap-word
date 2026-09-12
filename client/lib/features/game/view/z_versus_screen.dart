import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';

const _accentCycle = [ZAccent.indigo, ZAccent.teal, ZAccent.amber, ZAccent.coral];

/// ZVersus — true 1v1 multiplayer active-game screen: dual score header,
/// round indicator (visual-only placeholder — no round-tracking WS/backend
/// logic exists yet, see `GameConstants.multiplayerRoundsTotal`), a turn
/// banner with inline countdown, and the same chat-bubble shared chain as
/// ZPlay. No lives chip: unlike solo/daily (client-authoritative) and per
/// REDESIGN_PLAN.md §1 decision 1, multiplayer word validation is fully
/// server-authoritative — the server still ends the match on the first
/// mistake (word_rejected → loss_event, no grace period), so a lives count
/// here would be decorative and actively misleading. Needs a Go backend
/// change before it can be adopted for real, flagged rather than faked.
/// The caller (game_screen.dart) wraps this in the pre-existing continue-
/// window/disconnected overlays, unchanged and out of this stage's scope.
class ZVersusActiveScreen extends StatelessWidget {
  final GameActive state;

  const ZVersusActiveScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final z = context.z;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          children: [
            _Header(state: state),
            Expanded(child: _BubbleChain(state: state)),
            _Footer(state: state),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final GameActive state;

  const _Header({required this.state});

  String get _myUsername {
    final authState = getIt<AuthCubit>().state;
    return authState is AuthAuthenticated ? authState.username : 'تو';
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final myName = _myUsername;
    final opponentName = state.opponentUsername ?? 'حریف';
    final isMyTurn = state.isMyTurn;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter, ZSpacing.md, ZSpacing.screenGutter, ZSpacing.lg),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border(bottom: BorderSide(color: z.line)),
      ),
      child: Column(
        children: [
          // Canvas has no exit affordance for ZVersus, but a live match must
          // stay leaveable — added for real functional reasons, not style,
          // matching ZPlay/ZSolo's back-button-opens-end-game-dialog pattern.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [ZBackButton(onTap: () => zShowEndGameDialog(context))],
          ),
          const SizedBox(height: ZSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    LetterTile(letter: myName.isNotEmpty ? myName[0] : 'ت', size: 36, accent: ZAccent.teal),
                    const SizedBox(width: ZSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('تو', style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 13)),
                        Text(
                          toPersianDigits(state.score),
                          style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text('دست ۱', style: ZTypography.metaLabel.copyWith(color: z.ink40, fontWeight: FontWeight.w900)),
                  Text('از ${toPersianDigits(GameConstants.multiplayerRoundsTotal)}',
                      style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10.5)),
                ],
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(opponentName,
                            style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          toPersianDigits(state.opponentScore),
                          style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    LetterTile(letter: opponentName.isNotEmpty ? opponentName[0] : '؟', size: 36, accent: ZAccent.indigo),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.md),
          _TurnBanner(state: state, isMyTurn: isMyTurn, opponentName: opponentName),
        ],
      ),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  final GameActive state;
  final bool isMyTurn;
  final String opponentName;

  const _TurnBanner({required this.state, required this.isMyTurn, required this.opponentName});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final accent = isMyTurn ? z.teal : z.coral;
    final tint = isMyTurn ? z.tintTeal : z.tintCoral;
    final totalSeconds = state.mode == 'time_attack'
        ? GameConstants.timeAttackTurnTimerSec
        : GameConstants.classicTurnTimerSec;
    final fraction =
        totalSeconds <= 0 ? 0.0 : (state.turnTimeRemaining / totalSeconds).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.md, vertical: 7),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(ZRadius.tileMin + 1)),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: ZSpacing.sm),
          Text(
            isMyTurn ? 'نوبت تو' : 'نوبت $opponentName',
            style: ZTypography.metaLabel.copyWith(color: accent, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          const SizedBox(width: ZSpacing.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZRadius.chip),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: Colors.black.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Text(
            toPersianDigits(state.turnTimeRemaining),
            style: ZTypography.metaLabel.copyWith(color: accent, fontWeight: FontWeight.w900, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _BubbleChain extends StatefulWidget {
  final GameActive state;

  const _BubbleChain({required this.state});

  @override
  State<_BubbleChain> createState() => _BubbleChainState();
}

class _BubbleChainState extends State<_BubbleChain> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_BubbleChain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.wordChain.length != oldWidget.state.wordChain.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final state = widget.state;
    final chain = state.wordChain;
    final opponentName = state.opponentUsername ?? 'حریف';

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter, ZSpacing.lg, ZSpacing.screenGutter, 0),
      children: [
        if (chain.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZSpacing.lg),
            child: Row(
              children: [
                Expanded(child: Divider(color: z.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZSpacing.sm),
                  child: Text('شروع زنجیر',
                      style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10.5)),
                ),
                Expanded(child: Divider(color: z.line)),
              ],
            ),
          ),
        for (var i = 0; i < chain.length; i++) ...[
          _BubbleRow(
            word: chain[i],
            score: (i < state.wordOwners.length && state.wordOwners[i] == state.myPlayerId)
                ? _scoreForWordIndex(state, i)
                : null,
            isMine: i < state.wordOwners.length && state.wordOwners[i] == state.myPlayerId,
            distanceFromEnd: chain.length - 1 - i,
            accent: _accentCycle[i % _accentCycle.length],
            opponentLabel: opponentName,
          ),
          const SizedBox(height: ZSpacing.sm),
        ],
        _PlaceholderBubble(nextStartLetter: state.nextStartLetter, isMyTurn: state.isMyTurn),
        const SizedBox(height: ZSpacing.lg),
      ],
    );
  }

  // wordScores only accumulates the player's own words in submission order
  // (see GameBloc._handleWsWordAccepted) — it isn't parallel to wordChain
  // once the opponent's interspersed words are counted, so a "mine" bubble
  // must look up its score by move count among my own words, not by i.
  int? _scoreForWordIndex(GameActive state, int i) {
    var myMoveIndex = 0;
    for (var j = 0; j <= i; j++) {
      if (j < state.wordOwners.length && state.wordOwners[j] == state.myPlayerId) {
        if (j == i) return myMoveIndex < state.wordScores.length ? state.wordScores[myMoveIndex] : null;
        myMoveIndex++;
      }
    }
    return null;
  }
}

class _BubbleRow extends StatelessWidget {
  final String word;
  final int? score;
  final bool isMine;
  final int distanceFromEnd;
  final ZAccent accent;
  final String opponentLabel;

  const _BubbleRow({
    required this.word,
    required this.score,
    required this.isMine,
    required this.distanceFromEnd,
    required this.accent,
    required this.opponentLabel,
  });

  static const _sizes = [26.0, 26.0, 28.0, 30.0, 32.0];
  static const _fonts = [17.0, 17.0, 19.0, 21.0, 22.0];
  static const _opacities = [.5, .72, .85];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final embossed = distanceFromEnd <= 1;
    final rampIndex = (_sizes.length - 1 - distanceFromEnd).clamp(0, _sizes.length - 1);
    final tileSize = _sizes[rampIndex];
    final fontSize = _fonts[rampIndex];
    final opacity = embossed ? 1.0 : _opacities[distanceFromEnd.clamp(0, _opacities.length - 1)];

    final tile = LetterTile(letter: word[0], size: tileSize, accent: accent);
    final wordText = Text(
      word,
      style: ZTypography.chainWordHistory.copyWith(
        color: isMine ? z.onInkSurface : z.ink,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    );

    final bubble = Container(
      padding: EdgeInsets.symmetric(horizontal: embossed ? 14 : 12, vertical: embossed ? 10 : 9),
      decoration: BoxDecoration(
        color: isMine ? z.inkSurface : z.surface,
        borderRadius: BorderRadius.circular(embossed ? 18 : 16),
        border: isMine ? null : Border.all(color: z.line),
        boxShadow: embossed
            ? ZElevation.solidEdge(isMine ? z.inkSurfaceDeep : z.line, depth: ZElevation.cardDepth)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isMine
            ? [
                tile,
                const SizedBox(width: ZSpacing.sm),
                wordText,
                if (embossed) ...[
                  const SizedBox(width: ZSpacing.sm),
                  Text(
                    score != null ? 'تو · ‎+${toPersianDigits(score!)}' : 'تو',
                    style: ZTypography.metaLabel.copyWith(color: z.onInkSurfaceSoft, fontSize: 11),
                  ),
                ],
              ]
            : [
                Text(opponentLabel, style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10.5)),
                const SizedBox(width: ZSpacing.sm),
                wordText,
                const SizedBox(width: ZSpacing.sm),
                tile,
              ],
      ),
    );

    return Opacity(
      opacity: opacity,
      child: Align(
        alignment: isMine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: bubble,
      ),
    );
  }
}

class _PlaceholderBubble extends StatelessWidget {
  final String? nextStartLetter;
  final bool isMyTurn;

  const _PlaceholderBubble({required this.nextStartLetter, required this.isMyTurn});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Align(
      alignment: isMyTurn ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: z.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('کلمه‌ای با', style: ZTypography.body.copyWith(color: z.ink40, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: ZSpacing.sm),
            ZDashedTile(letter: nextStartLetter ?? '؟', size: 34),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final GameActive state;

  const _Footer({required this.state});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final isGuest = state.guestHintUsesLeft != 999;
    final hintAvailable = (!isGuest || state.guestHintUsesLeft > 0) && state.isMyTurn;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter, ZSpacing.md, ZSpacing.screenGutter, ZSpacing.lg),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border(top: BorderSide(color: z.line)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ZPowerupTile(
                icon: const ZHintIcon(),
                count: state.guestHintUsesLeft == 999 ? 0 : state.guestHintUsesLeft,
                label: 'راهنما',
                enabled: hintAvailable,
                onTap: () => context.read<GameBloc>().add(const HintRequested()),
              ),
              const SizedBox(width: ZSpacing.sm),
              ZPowerupTile(
                icon: Transform.rotate(
                  angle: 0.785398,
                  child: Container(width: 20, height: 20, decoration: BoxDecoration(color: z.teal, borderRadius: BorderRadius.circular(5))),
                ),
                count: 0,
                label: 'انجماد حریف',
                enabled: false,
              ),
              const SizedBox(width: ZSpacing.sm),
              ZPowerupTile(
                icon: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: z.amber, width: 4)),
                  child: const SizedBox(width: 22, height: 22),
                ),
                count: 0,
                label: 'وقت بیشتر',
                enabled: false,
              ),
              const SizedBox(width: ZSpacing.sm),
              ZPowerupTile(
                icon: Container(width: 19, height: 22, decoration: BoxDecoration(color: z.coral, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)))),
                count: 0,
                label: 'سپر',
                enabled: false,
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.md),
          ZWordInput(
            startLetter: state.nextStartLetter,
            enabled: state.isMyTurn && !state.opponentContinueWindowActive,
            hintWord: state.hintWord,
            isOpponentThinking: !state.isMyTurn,
            opponentLabel: state.opponentUsername ?? 'حریف',
            onSubmit: (word) => context.read<GameBloc>().add(WordSubmitted(word)),
          ),
        ],
      ),
    );
  }
}
