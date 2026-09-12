import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/widgets/continue_prompt.dart';
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

  void _handleContinue(BuildContext context, String method) async {
    final monetization = getIt<MonetizationService>();
    if (method == 'ad') {
      final watched = await monetization.showRewardedAd();
      if (!watched || !context.mounted) return;
    } else if (method == 'coins') {
      final spent = monetization.spendCoins(25);
      if (!spent) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not enough coins.')),
          );
        }
        return;
      }
    }
    if (context.mounted) {
      context.read<GameBloc>().add(ContinueRequested(method));
    }
  }

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
        if (state is GameLoading || state is GameInitial) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is GameError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: const TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        }

        if (state is GameOver) {
          // Phase 17 — solo/vs-AI game-overs always carry an opponentType;
          // true multiplayer's WS-driven GameOver never sets one (see
          // GameBloc._handleWsLossEvent/_handleWsGameOver). Multiplayer
          // (ZVersus) isn't redesigned yet — Stage 4 — so it keeps the
          // legacy ContinuePrompt/_GameOverScreen pair.
          if (state.opponentType != null) {
            return ZOverScreen(state: state);
          }
          if (!state.isSaved &&
              state.canContinue &&
              state.continueTimeRemaining > 0) {
            return Scaffold(
              backgroundColor: AppColors.background,
              body: ContinuePrompt(
                state: state,
                onContinue: (method) =>
                    _handleContinue(context, method),
                onAcceptDefeat: () =>
                    context.read<GameBloc>().add(const AcceptDefeat()),
              ),
            );
          }
          return _GameOverScreen(state: state);
        }

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
                  opponentName: state.opponentUsername ?? 'Opponent',
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
// Opponent continue-window overlay
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
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top,
                    size: 40, color: AppColors.secondary),
                const SizedBox(height: 16),
                Text(
                  '$opponentName deciding…',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$remaining s',
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'They can watch an ad or spend coins to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Disconnected banner
// ---------------------------------------------------------------------------

class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.error.withValues(alpha: 0.9),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text(
                'Opponent disconnected — waiting 30s…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Game over
// ---------------------------------------------------------------------------

class _GameOverScreen extends StatelessWidget {
  final GameOver state;

  const _GameOverScreen({required this.state});

  void _navigateHome(BuildContext context) async {
    await getIt<MonetizationService>().showInterstitialAd();
    if (context.mounted) context.go('/home');
  }

  String get _reasonTitle => switch (state.reason) {
        'time_limit' => 'Time\'s Up!',
        'ended_by_user' => 'Game Ended',
        'timeout' => 'Timer Ran Out!',
        'opponent_disconnected' => 'Opponent Left',
        'max_words' => 'Challenge Complete!',
        _ => 'Game Over',
      };

  @override
  Widget build(BuildContext context) {
    final isMultiplayer = state.isMultiplayer;

    // For multiplayer result banner
    Widget? resultBanner;
    if (isMultiplayer && state.winnerId != null) {
      final iWonMatch = state.score > state.opponentScore ||
          state.reason == 'opponent_disconnected';
      resultBanner = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: iWonMatch
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: iWonMatch ? AppColors.success : AppColors.error,
          ),
        ),
        child: Column(
          children: [
            Text(
              iWonMatch ? '🏆 YOU WIN!' : '😞 YOU LOSE',
              style: TextStyle(
                color: iWonMatch ? AppColors.success : AppColors.error,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    // VS AI: show win/loss banner based on who made the mistake
    if (!isMultiplayer &&
        state.opponentType != null &&
        state.opponentType!.startsWith('ai_') &&
        state.opponentScore > 0) {
      final scoredMore = state.score > state.opponentScore;
      resultBanner = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: scoredMore
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scoredMore ? AppColors.success : AppColors.error,
          ),
        ),
        child: Column(
          children: [
            Text(
              scoredMore ? '🏆 YOU WIN!' : '😞 YOU LOSE',
              style: TextStyle(
                color: scoredMore ? AppColors.success : AppColors.error,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
              if (resultBanner == null)
                const Text('🏁', style: TextStyle(fontSize: 60)),
              if (resultBanner != null) resultBanner,
              const SizedBox(height: 16),
              if (resultBanner == null)
                Text(
                  _reasonTitle,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 28),
              if (isMultiplayer || state.opponentScore > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: _ResultCard(
                        label: 'YOUR SCORE',
                        value: state.score.toString(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ResultCard(
                        label: 'OPP SCORE',
                        value: state.opponentScore.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ResultCard(
                  label: 'WORDS',
                  value: state.chainLength.toString(),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _ResultCard(
                        label: 'SCORE',
                        value: state.score.toString(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ResultCard(
                        label: 'WORDS',
                        value: state.chainLength.toString(),
                      ),
                    ),
                  ],
                ),
                if (state.wordChain.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _ResultCard(
                    label: 'LONGEST WORD',
                    value: state.wordChain
                        .reduce((a, b) => a.length >= b.length ? a : b)
                        .toUpperCase(),
                  ),
                ],
              ],
              const SizedBox(height: 40),
              // Daily challenge: show loading indicator while sync completes, then auto-navigates
              if (state.mode == 'daily') ...[
                if (!state.isSaved) ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Saving your result…',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ] else ...[
                ElevatedButton(
                  onPressed: () => _navigateHome(context),
                  child: const Text('Back to Home'),
                ),
                  if (!isMultiplayer) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        context.pushReplacement(
                          '/game',
                          extra: GameRouteArgs(
                            mode: state.mode,
                            opponentType: state.opponentType ?? 'solo',
                          ),
                        );
                      },
                      child: const Text('Play Again'),
                    ),
                  ],
              ],
            ],
          ),
        ),
      ),
    ),
  ),
),
),
);
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final String value;

  const _ResultCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
