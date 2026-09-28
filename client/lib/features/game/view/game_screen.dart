import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/z_over_screen.dart';
import 'package:wordchain/features/game/view/z_play_screen.dart';
import 'package:wordchain/features/game/view/z_solo_screen.dart';
import 'package:wordchain/features/game/view/z_versus_screen.dart';

class GameRouteArgs {
  final String mode; // classic | time_attack | daily
  final String opponentType; // solo | ai_easy | ai_medium | ai_hard | multiplayer
  final int? resumeMatchId;
  final String? roomId; // multiplayer WS room
  final String? myPlayerId; // authenticated user's UUID
  final String? startLetter; // daily challenge: first required letter

  const GameRouteArgs({
    required this.mode,
    required this.opponentType,
    this.resumeMatchId,
    this.roomId,
    this.myPlayerId,
    this.startLetter,
  });

  bool get isMultiplayer => roomId != null;
}

class GameScreen extends StatelessWidget {
  final GameRouteArgs args;

  const GameScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GameBloc(
        gameRepository: getIt(),
        dictionaryService: getIt(),
        statsDao: getIt(),
        syncService: getIt(),
        prefs: getIt(),
        wsService: getIt(),
      )..add(GameStarted(
          mode: args.mode,
          opponentType: args.opponentType,
          resumeMatchId: args.resumeMatchId,
          roomId: args.roomId,
          myPlayerId: args.myPlayerId,
          startLetter: args.startLetter,
        )),
      child: const _GameView(),
    );
  }
}

class _GameView extends StatelessWidget {
  const _GameView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GameBloc, GameState>(
      listenWhen: (prev, curr) =>
          curr is GameOver && curr.isSaved && prev is GameOver && !prev.isSaved,
      listener: (context, state) {
        // Daily challenge: auto-navigate to result screen once saved
        if (state is GameOver && state.mode == 'daily') {
          context.go('/daily');
        }
      },
      builder: (context, state) {
        final z = context.z;

        if (state is GameLoading || state is GameInitial) {
          return Scaffold(
            backgroundColor: z.paper,
            body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: z.indigo)),
          );
        }

        if (state is GameError) {
          return Scaffold(
            backgroundColor: z.paper,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(ZSpacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, color: z.coral, size: 44),
                      const SizedBox(height: ZSpacing.lg),
                      Text(
                        state.message,
                        textAlign: TextAlign.center,
                        style: ZTypography.body.copyWith(color: z.ink60),
                      ),
                      const SizedBox(height: ZSpacing.xxl),
                      NeutralButton(label: 'بازگشت', onPressed: () => context.pop()),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ZOver handles solo, vs-AI and true multiplayer (see its dispatch).
        if (state is GameOver) return ZOverScreen(state: state);

        if (state is GameActive) {
          if (state.opponentType == 'solo') {
            return ZSoloActiveScreen(state: state);
          }
          if (state.isVsAI) {
            return ZPlayActiveScreen(state: state);
          }
          return Stack(
            children: [
              ZVersusActiveScreen(state: state),
              if (state.opponentContinueWindowActive)
                _OpponentContinueOverlay(
                  remaining: state.opponentContinueWindowRemaining,
                  opponentName: state.opponentUsername ?? 'حریف',
                ),
              if (state.opponentDisconnected) const _DisconnectedBanner(),
            ],
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Opponent continue-window overlay — "Opponent deciding…" (CLAUDE.md
// Continue Rules #4). No canvas design; derived from the token system.
// ---------------------------------------------------------------------------

class _OpponentContinueOverlay extends StatelessWidget {
  final int remaining;
  final String opponentName;

  const _OpponentContinueOverlay({
    required this.remaining,
    required this.opponentName,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Positioned.fill(
      child: ColoredBox(
        color: z.paper.withValues(alpha: 0.88),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZSpacing.xxxl),
            child: SolidCard(
              radius: ZRadius.sheetMin,
              padding: const EdgeInsets.all(ZSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: z.tintCoral,
                      borderRadius: BorderRadius.circular(ZRadius.cardMin),
                    ),
                    child: Text(
                      toPersianDigits(remaining),
                      style: ZTypography.display.copyWith(color: z.coral, fontSize: 30),
                    ),
                  ),
                  const SizedBox(height: ZSpacing.lg),
                  Text(
                    '$opponentName دارد تصمیم می‌گیرد…',
                    textAlign: TextAlign.center,
                    style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 15),
                  ),
                  const SizedBox(height: ZSpacing.sm),
                  Text(
                    'حریف می‌تواند با تماشای ویدیو یا خرج سکه ادامه دهد.',
                    textAlign: TextAlign.center,
                    style: ZTypography.body.copyWith(color: z.ink60),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Disconnected banner — server holds the room for the 30s grace window.
// ---------------------------------------------------------------------------

class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return PositionedDirectional(
      top: MediaQuery.of(context).padding.top + 60,
      start: ZSpacing.screenGutter,
      end: ZSpacing.screenGutter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: 10),
        decoration: BoxDecoration(
          color: z.coral,
          borderRadius: BorderRadius.circular(ZRadius.tileMax),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: z.onCoral, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'اتصال حریف قطع شد — ${toPersianDigits(GameConstants.reconnectGraceSec)} ثانیه صبر می‌کنیم…',
                style: ZTypography.metaLabel.copyWith(color: z.onCoral, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
