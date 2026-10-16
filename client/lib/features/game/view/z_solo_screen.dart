import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

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
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: context.zs.sky3,
      // The scene stays put behind the keyboard; the content pads itself.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeSceneBackground(calm: true)),
          Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SafeArea(
              bottom: keyboard == 0,
              child: Column(
                children: [
                  _Header(state: state, record: _recordChainLength),
                  Expanded(
                    child: ZSpineChain(
                      words: state.wordChain,
                      scores: state.wordScores,
                      nextStartLetter: state.nextStartLetter,
                    ),
                  ),
                  _Footer(state: state, keyboardOpen: keyboard > 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final GameActive state;
  final int record;

  const _Header({required this.state, required this.record});

  @override
  Widget build(BuildContext context) {
    final isDaily = state.mode == 'daily';
    final compact = MediaQuery.sizeOf(context).width < 350;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          Row(
            children: [
              ZGameBackButton(onTap: () => zShowEndGameDialog(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Center(
                  child: ZScorePill(
                    score: state.score,
                    title: isDaily ? 'چالش روزانه' : 'تک‌نفره',
                    // Daily is a fixed, once-a-day variant — no mode toggle
                    // (switching would silently abandon the tracked attempt).
                    subtitle:
                        isDaily
                            ? 'حداکثر ${toPersianDigits(GameConstants.dailyMaxWords)} کلمه'
                            : '${toPersianDigits(GameConstants.classicTurnTimerSec)} ثانیه',
                    compact: compact,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ZTimerRing(
                secondsRemaining: state.turnTimeRemaining,
                totalSeconds: GameConstants.classicTurnTimerSec,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ZLivesChip(
                lives: state.livesRemaining,
                maxLives: GameConstants.soloLives,
              ),
              const SizedBox(width: 8),
              ZWordsChip(words: state.wordChain.length, record: record),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final GameActive state;
  final bool keyboardOpen;

  const _Footer({required this.state, required this.keyboardOpen});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, keyboardOpen ? 8 : 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.lastMistakeReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChunkyBox(
                fill: z.tintCoral,
                depth: ZGame.depthSm,
                radius: 14,
                highlight: false,
                borderWidth: ZGame.outlineInner,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  'کلمهٔ اشتباه — یک جان از دست دادی!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: zs.coralInk,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ZWordInput(
            chunky: true,
            startLetter: state.nextStartLetter,
            enabled: state.isMyTurn,
            hintWord: state.hintWord,
            onSubmit:
                (word) => context.read<GameBloc>().add(WordSubmitted(word)),
          ),
          const SizedBox(height: 14),
          ZPowerupBar(
            state: state,
            types: const ['hint', 'extra_time', 'shield'],
            chunky: true,
          ),
        ],
      ),
    );
  }
}
