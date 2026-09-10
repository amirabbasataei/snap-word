import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
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

/// ZSolo — the true solo (no opponent) active-game screen: vertical spine
/// chain renderer, stat strip (chain length / personal record / lives),
/// and the low-key "زمان‌دار" mode toggle (this screen's own addition —
/// not in the canvas; see REDESIGN_PLAN.md entry-flow note).
class ZSoloActiveScreen extends StatefulWidget {
  final GameActive state;

  const ZSoloActiveScreen({super.key, required this.state});

  @override
  State<ZSoloActiveScreen> createState() => _ZSoloActiveScreenState();
}

class _ZSoloActiveScreenState extends State<ZSoloActiveScreen> {
  int _recordChainLength = 0;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    try {
      final stats = await getIt<StatsDao>().getStats();
      if (mounted) setState(() => _recordChainLength = stats?.bestMatchStreak ?? 0);
    } catch (_) {
      // Best-effort — stat strip just shows ۰ until this resolves.
    }
  }

  void _switchMode(BuildContext context, String targetMode) {
    final args = GameRouteArgs(mode: targetMode, opponentType: 'solo');
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
            _Header(
              state: state,
              recordChainLength: _recordChainLength,
              onSwitchMode: (mode) => _switchMode(context, mode),
            ),
            Expanded(child: _ChainList(state: state)),
            _Footer(state: state, recordChainLength: _recordChainLength),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final GameActive state;
  final int recordChainLength;
  final void Function(String targetMode) onSwitchMode;

  const _Header({
    required this.state,
    required this.recordChainLength,
    required this.onSwitchMode,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
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
                    Text('تک‌نفره',
                        style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 14)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isTimeAttack ? 'زمان‌دار · ۸ ثانیه هر نوبت' : 'بی‌وقفه · بدون حریف',
                            style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: ZSpacing.sm),
                        GestureDetector(
                          onTap: () => onSwitchMode(isTimeAttack ? 'classic' : 'time_attack'),
                          child: Text(
                            isTimeAttack ? '🎯 حالت کلاسیک' : '⏱ حالت زمان‌دار',
                            style: ZTypography.metaLabel.copyWith(
                              color: z.indigo,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
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
                    style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  Text('امتیاز', style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.md),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: toPersianDigits(state.wordChain.length),
                  label: 'طول زنجیر',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _StatTile(
                  value: toPersianDigits(recordChainLength),
                  label: 'رکورد تو',
                  valueColor: z.teal,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: isTimeAttack
                    ? _StatTile(
                        value: toPersianDigits(state.matchTimeRemaining ?? 0),
                        label: 'زمان کل',
                      )
                    : _LivesTile(livesRemaining: state.livesRemaining, maxLives: GameConstants.soloLives),
              ),
            ],
          ),
          ZTimerRow(
            secondsRemaining: state.turnTimeRemaining,
            totalSeconds: isTimeAttack
                ? GameConstants.timeAttackTurnTimerSec
                : GameConstants.classicTurnTimerSec,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const _StatTile({
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: z.paper,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: z.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: ZTypography.cardTitle.copyWith(color: valueColor ?? z.ink, fontSize: 15, fontWeight: FontWeight.w900),
          ),
          Text(label, style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10)),
        ],
      ),
    );
  }
}

class _LivesTile extends StatelessWidget {
  final int livesRemaining;
  final int maxLives;

  const _LivesTile({required this.livesRemaining, required this.maxLives});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: z.paper,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: z.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < maxLives; i++) ...[
                Container(
                  width: 9,
                  height: 12,
                  margin: EdgeInsetsDirectional.only(end: i == maxLives - 1 ? 0 : 3),
                  decoration: BoxDecoration(
                    color: i < livesRemaining ? z.coral : z.wash,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text('${toPersianDigits(livesRemaining)} جان',
              style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10)),
        ],
      ),
    );
  }
}

/// The graduated size/opacity ramp for the last N words — matches the
/// canvas exactly; entries further back than the window render at the
/// dimmest/smallest step (a sensible fade floor for a long chain).
const _rampSizes = [26.0, 26.0, 26.0, 26.0, 28.0, 28.0, 30.0, 30.0];
const _rampFonts = [16.0, 16.0, 16.0, 17.0, 18.0, 18.0, 19.0, 20.0];
const _rampOpacity = [.4, .45, .5, .58, .68, .78, .88, 1.0];

class _ChainList extends StatefulWidget {
  final GameActive state;

  const _ChainList({required this.state});

  @override
  State<_ChainList> createState() => _ChainListState();
}

class _ChainListState extends State<_ChainList> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_ChainList oldWidget) {
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
    final state = widget.state;
    final chain = state.wordChain;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter, ZSpacing.lg, ZSpacing.screenGutter, 0),
      children: [
        for (var i = 0; i < chain.length; i++) ...[
          _ChainRow(
            index: i,
            word: chain[i],
            score: i < state.wordScores.length ? state.wordScores[i] : null,
            distanceFromEnd: chain.length - 1 - i,
          ),
          if (i < chain.length - 1) const _ChainGap(),
        ],
        if (chain.isNotEmpty) const SizedBox(height: ZSpacing.lg),
        _NextWordRow(nextStartLetter: state.nextStartLetter),
        const SizedBox(height: ZSpacing.lg),
      ],
    );
  }
}

class _ChainGap extends StatelessWidget {
  const _ChainGap();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SizedBox(
      height: 13,
      child: Row(
        children: [
          SizedBox(width: 32, child: Center(child: Container(width: 2, height: 13, color: z.line))),
        ],
      ),
    );
  }
}

class _ChainRow extends StatelessWidget {
  final int index;
  final String word;
  final int? score;
  final int distanceFromEnd;

  const _ChainRow({
    required this.index,
    required this.word,
    required this.score,
    required this.distanceFromEnd,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final accent = _accentCycle[index % _accentCycle.length];

    if (distanceFromEnd == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: ZSpacing.md),
        child: Row(
          children: [
            SizedBox(width: 32, child: Center(child: LetterTile(letter: word[0], size: 32, accent: accent))),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      word,
                      style: ZTypography.chainWordActive.copyWith(color: z.ink, fontSize: 24),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: ZSpacing.sm),
                  if (score != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: z.tintTeal, borderRadius: BorderRadius.circular(ZRadius.chip)),
                      child: Text(
                        '‎+${toPersianDigits(score!)} · تازه',
                        style: ZTypography.metaLabel.copyWith(color: z.teal, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final rampIndex = (_rampSizes.length - 1 - distanceFromEnd).clamp(0, _rampSizes.length - 1);
    final size = _rampSizes[rampIndex];
    final fontSize = _rampFonts[rampIndex];
    final opacity = _rampOpacity[rampIndex];

    return Padding(
      padding: const EdgeInsets.only(bottom: ZSpacing.md),
      child: Opacity(
        opacity: opacity,
        child: Row(
          children: [
            SizedBox(width: 32, child: Center(child: LetterTile(letter: word[0], size: size, accent: accent))),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      word,
                      style: ZTypography.chainWordHistory.copyWith(color: z.ink, fontSize: fontSize),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: ZSpacing.sm),
                  if (score != null)
                    Text(
                      '${toPersianDigits(index + 1)} · ‎+${toPersianDigits(score!)}',
                      style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 10.5),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextWordRow extends StatelessWidget {
  final String? nextStartLetter;

  const _NextWordRow({required this.nextStartLetter});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Center(
            child: ZDashedTile(letter: nextStartLetter ?? '؟', size: 34),
          ),
        ),
        const SizedBox(width: ZSpacing.md),
        Expanded(
          child: Text(
            nextStartLetter != null ? 'حالا کلمه‌ای با «$nextStartLetter»' : 'اولین کلمه رو بنویس',
            style: ZTypography.body.copyWith(color: z.ink40, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  final GameActive state;
  final int recordChainLength;

  const _Footer({required this.state, required this.recordChainLength});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final isGuest = state.guestHintUsesLeft != 999;
    final hintAvailable = (!isGuest || state.guestHintUsesLeft > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter, ZSpacing.md, ZSpacing.screenGutter, ZSpacing.lg),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border(top: BorderSide(color: z.line)),
      ),
      child: Column(
        children: [
          if (state.lastMistakeReason != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: ZSpacing.sm),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: z.tintCoral, borderRadius: BorderRadius.circular(ZRadius.tileMax)),
              child: Text(
                'کلمهٔ اشتباه — یک جان از دست دادی!',
                textAlign: TextAlign.center,
                style: ZTypography.metaLabel.copyWith(color: z.coral, fontWeight: FontWeight.w700),
              ),
            ),
          ],
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
            onSubmit: (word) => context.read<GameBloc>().add(WordSubmitted(word)),
          ),
        ],
      ),
    );
  }
}
