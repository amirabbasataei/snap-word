import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';

const _accentCycle = [ZAccent.indigo, ZAccent.teal, ZAccent.amber, ZAccent.coral];

const _difficultyLabels = {
  'ai_easy': 'آسان',
  'ai_medium': 'متوسط',
  'ai_hard': 'سخت',
};

const _difficultyTiers = {'ai_easy': 1, 'ai_medium': 2, 'ai_hard': 3};

/// ZPlay — vs-AI active-game screen: chat-bubble chain renderer (opponent
/// on the "start" side, you inverted on the "end" side), no lives (design
/// only shows lives for true solo — see REDESIGN_PLAN.md §1). Carries the
/// same inline زمان‌دار/کلاسیک mode-switch toggle as ZSolo (see
/// REDESIGN_PLAN.md's VS-AI entry-flow note) so Time Attack vs AI stays
/// reachable without a pre-game picker sheet.
class ZPlayActiveScreen extends StatefulWidget {
  final GameActive state;

  const ZPlayActiveScreen({super.key, required this.state});

  @override
  State<ZPlayActiveScreen> createState() => _ZPlayActiveScreenState();
}

class _ZPlayActiveScreenState extends State<ZPlayActiveScreen> {
  void _switchMode(BuildContext context, String targetMode) {
    final args = GameRouteArgs(mode: targetMode, opponentType: widget.state.opponentType);
    if (widget.state.wordChain.isEmpty) {
      context.pushReplacement('/game', extra: args);
      return;
    }

    final z = context.z;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: z.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZRadius.cardMax)),
        child: Padding(
          padding: const EdgeInsets.all(ZSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                targetMode == 'time_attack' ? 'شروع دوباره در حالت زمان‌دار؟' : 'شروع دوباره در حالت کلاسیک؟',
                style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 17),
              ),
              const SizedBox(height: ZSpacing.sm),
              Text('پیشرفت این بازی از دست می‌رود.',
                  style: ZTypography.body.copyWith(color: z.ink60)),
              const SizedBox(height: ZSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('انصراف'),
                    ),
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        context.pushReplacement('/game', extra: args);
                      },
                      child: const Text('شروع دوباره'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final state = widget.state;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          children: [
            _Header(state: state, onSwitchMode: (mode) => _switchMode(context, mode)),
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
  final void Function(String targetMode) onSwitchMode;

  const _Header({required this.state, required this.onSwitchMode});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final difficulty = _difficultyLabels[state.opponentType] ?? '';
    final tier = _difficultyTiers[state.opponentType] ?? 1;
    final isTimeAttack = state.mode == 'time_attack';

    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter, ZSpacing.md, ZSpacing.screenGutter, ZSpacing.lg),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border(bottom: BorderSide(color: z.line)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZBackButton(onTap: () => zShowEndGameDialog(context)),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('حریف هوشمند · $difficulty',
                        style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 14)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'سطح ${toPersianDigits(tier)} از ۳ · ${state.isMyTurn ? 'نوبت تو' : 'نوبت حریف'}',
                            style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: ZSpacing.sm),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSwitchMode(isTimeAttack ? 'classic' : 'time_attack'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: ZSpacing.sm),
                            child: Text(
                              isTimeAttack ? '🎯 حالت کلاسیک' : '⏱ حالت زمان‌دار',
                              style: ZTypography.metaLabel.copyWith(
                                color: z.indigo,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    toPersianDigits(state.score),
                    style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  Text('امتیاز', style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10.5)),
                ],
              ),
            ],
          ),
          ZTimerRow(
            secondsRemaining: state.turnTimeRemaining,
            totalSeconds: state.mode == 'time_attack'
                ? GameConstants.timeAttackTurnTimerSec
                : GameConstants.classicTurnTimerSec,
          ),
        ],
      ),
    );
  }
}

const _bubbleSizes = [26.0, 26.0, 28.0, 30.0, 32.0];
const _bubbleFonts = [17.0, 17.0, 19.0, 21.0, 22.0];
const _bubbleOpacity = [.5, .72, .85];

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
    final difficulty = _difficultyLabels[state.opponentType] ?? 'حریف';

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
        for (var i = 0, myMoveIndex = 0; i < chain.length; i++) ...[
          _BubbleRow(
            word: chain[i],
            // wordScores only ever accumulates the player's own words (see
            // GameBloc._onWordSubmitted) — it isn't parallel to wordChain
            // once the AI's interspersed words are counted, so a "mine"
            // bubble must look up its score by move count, not by i.
            score: (i >= state.wordOwners.length || state.wordOwners[i] == 'player')
                ? (myMoveIndex < state.wordScores.length ? state.wordScores[myMoveIndex++] : null)
                : null,
            isMine: i >= state.wordOwners.length || state.wordOwners[i] == 'player',
            distanceFromEnd: chain.length - 1 - i,
            accent: _accentCycle[i % _accentCycle.length],
            opponentLabel: difficulty,
          ),
          const SizedBox(height: ZSpacing.sm),
        ],
        _PlaceholderBubble(nextStartLetter: state.nextStartLetter, isMyTurn: state.isMyTurn),
        const SizedBox(height: ZSpacing.lg),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final embossed = distanceFromEnd <= 1;
    final rampIndex =
        (_bubbleSizes.length - 1 - distanceFromEnd).clamp(0, _bubbleSizes.length - 1);
    final tileSize = _bubbleSizes[rampIndex];
    final fontSize = _bubbleFonts[rampIndex];
    final opacity = embossed ? 1.0 : _bubbleOpacity[distanceFromEnd.clamp(0, _bubbleOpacity.length - 1)];

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
            enabled: state.isMyTurn,
            hintWord: state.hintWord,
            isOpponentThinking: !state.isMyTurn,
            opponentLabel: _difficultyLabels[state.opponentType] ?? 'حریف',
            onSubmit: (word) => context.read<GameBloc>().add(WordSubmitted(word)),
          ),
        ],
      ),
    );
  }
}
