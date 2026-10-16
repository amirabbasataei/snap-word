import 'package:flutter/material.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_game_chain.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_game_scaffold.dart';

/// ZSolo — the true solo (no opponent) active-game screen in the "A ·
/// mascot-led" language (canvas turn 7, `ZSoloA`): calm sky scene, floating
/// chunky HUD (back, score pill, countdown ring, lives, words/record), the
/// linked word-tile chain, then the input card and power-ups. Also used by
/// the Daily Challenge (same screen, different subtitle).
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
      if (mounted) {
        setState(() => _recordChainLength = stats?.bestMatchStreak ?? 0);
      }
    } catch (_) {
      // Best-effort — the record chip just shows ۰ until this resolves.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ZGameScaffold(
      header: _Header(state: state, record: _recordChainLength),
      body: ZSpineChain(
        words: state.wordChain,
        scores: state.wordScores,
        nextStartLetter: state.nextStartLetter,
      ),
      footer: ZGameFooter(state: state, banner: _mistakeBanner(context, state)),
    );
  }
}

/// «کلمهٔ اشتباه — یک جان از دست دادی!» — shown for a moment after a lost life.
Widget? _mistakeBanner(BuildContext context, GameActive state) {
  if (state.lastMistakeReason == null) return null;
  return ChunkyBox(
    fill: context.z.tintCoral,
    depth: ZGame.depthSm,
    radius: 14,
    highlight: false,
    borderWidth: ZGame.outlineInner,
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text(
      'کلمهٔ اشتباه — یک جان از دست دادی!',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: context.zs.coralInk,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  final GameActive state;
  final int record;

  const _Header({required this.state, required this.record});

  @override
  Widget build(BuildContext context) {
    final isDaily = state.mode == 'daily';
    final compact = MediaQuery.sizeOf(context).width < 350;

    return ZGameHeader(
      center: Center(
        child: ZScorePill(
          score: state.score,
          title: isDaily ? 'چالش روزانه' : 'تک‌نفره',
          // Daily is a fixed, once-a-day variant — no mode toggle (switching
          // would silently abandon the tracked attempt).
          subtitle:
              isDaily
                  ? 'حداکثر ${toPersianDigits(GameConstants.dailyMaxWords)} کلمه'
                  : '${toPersianDigits(GameConstants.classicTurnTimerSec)} ثانیه',
          compact: compact,
        ),
      ),
      ring: ZTimerRing(
        secondsRemaining: state.turnTimeRemaining,
        totalSeconds: GameConstants.classicTurnTimerSec,
      ),
      below: Row(
        children: [
          ZLivesChip(
            lives: state.livesRemaining,
            maxLives: GameConstants.soloLives,
          ),
          const SizedBox(width: 8),
          ZWordsChip(words: state.wordChain.length, record: record),
        ],
      ),
    );
  }
}
