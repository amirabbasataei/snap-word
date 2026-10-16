import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_game_bubbles.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_game_scaffold.dart';

const _difficultyLabels = {
  'ai_easy': 'آسان',
  'ai_medium': 'متوسط',
  'ai_hard': 'سخت',
};

const _difficultyTiers = {'ai_easy': 1, 'ai_medium': 2, 'ai_hard': 3};

/// ZPlay — the vs-AI active-game screen in the "A · mascot-led" language
/// (canvas turn 7, `ZPlayA`): calm sky scene, a head-to-head score pill with
/// the turn chip, the countdown ring, the level/bonus chips, the shared chain
/// as chunky chat bubbles (you on the start side, the opponent on the end
/// side), then the input card and power-ups. No lives in this mode.
class ZPlayActiveScreen extends StatelessWidget {
  final GameActive state;

  const ZPlayActiveScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthCubit>().state;
    final initial = avatarInitial(
      auth is AuthAuthenticated ? auth.username : null,
    );

    return ZGameScaffold(
      header: _Header(state: state, initial: initial),
      body: ZBubbleChain(
        entries: _entries(state),
        nextStartLetter: state.nextStartLetter,
        myTurn: state.isMyTurn,
        myInitial: initial,
      ),
      footer: ZGameFooter(
        state: state,
        opponentLabel: 'حریف هوشمند',
        longWordMinLength: GameConstants.longWordBonusMinLength,
      ),
    );
  }
}

/// Maps the shared chain to bubbles. `wordScores` only ever accumulates the
/// player's own words (see `GameBloc._onWordSubmitted`) — it isn't parallel to
/// `wordChain` once the AI's interspersed words are counted, so a "mine"
/// bubble looks its score up by move count, not by chain index.
List<ZBubbleEntry> _entries(GameActive state) {
  final entries = <ZBubbleEntry>[];
  var myMove = 0;
  for (var i = 0; i < state.wordChain.length; i++) {
    final mine =
        i >= state.wordOwners.length || state.wordOwners[i] == 'player';
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

class _Header extends StatelessWidget {
  final GameActive state;
  final String initial;

  const _Header({required this.state, required this.initial});

  @override
  Widget build(BuildContext context) {
    final level = _difficultyLabels[state.opponentType] ?? '';
    final tier = _difficultyTiers[state.opponentType] ?? 1;

    return ZGameHeader(
      center: ZVersusPill(
        myAvatar:
            (size) => ZDiscAvatar.me(context, letter: initial, size: size),
        myLabel: 'تو',
        myScore: state.score,
        opponentAvatar: (size) => ZDiscAvatar.robot(context, size: size),
        opponentLabel: level,
        opponentScore: state.opponentScore,
        myTurn: state.isMyTurn,
        myTurnLabel: 'نوبت تو',
        opponentTurnLabel: 'نوبت حریف',
      ),
      ring: ZTimerRing(
        secondsRemaining: state.turnTimeRemaining,
        totalSeconds: GameConstants.classicTurnTimerSec,
        calm: true,
        paused: !state.isMyTurn,
      ),
      below: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [_LevelChip(level: level, tier: tier), const _BonusChip()],
      ),
    );
  }
}

/// «حریف هوشمند · آسان ●○○» — the opponent's level with a 1–3 dot gauge.
class _LevelChip extends StatelessWidget {
  final String level;
  final int tier;

  const _LevelChip({required this.level, required this.tier});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Semantics(
      label:
          'حریف هوشمند · $level، سطح ${toPersianDigits(tier)} از ${toPersianDigits(3)}',
      excludeSemantics: true,
      child: ChunkyBox(
        fill: z.surface,
        depth: 0,
        radius: 999,
        highlight: false,
        borderWidth: ZGame.outlineInner,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'حریف هوشمند · $level',
              style: TextStyle(
                color: z.ink,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 6),
            for (var i = 1; i <= 3; i++) ...[
              if (i > 1) const SizedBox(width: 3),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i <= tier ? z.amber : z.wash,
                  shape: BoxShape.circle,
                  border: Border.all(color: zs.outline, width: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// «۷ حرف به بالا = دوبرابر» — the long-word bonus rule of vs-AI/solo play.
class _BonusChip extends StatelessWidget {
  const _BonusChip();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.amber,
      depth: 0,
      radius: 999,
      highlight: false,
      borderWidth: ZGame.outlineInner,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // Not `alignment:` — that would stretch the chip across the Wrap.
      child: Center(
        widthFactor: 1,
        child: Text(
          '${toPersianDigits(GameConstants.longWordBonusMinLength)} حرف به بالا = دوبرابر',
          style: TextStyle(
            color: z.onAmber,
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            height: 1,
          ),
        ),
      ),
    );
  }
}
