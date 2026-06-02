import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/continue_prompt.dart';
import 'package:wordchain/features/game/view/widgets/timer_bar.dart';
import 'package:wordchain/features/game/view/widgets/word_chain_list.dart';
import 'package:wordchain/features/game/view/widgets/word_input.dart';

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
          if (!state.isSaved &&
              state.canContinue &&
              state.continueTimeRemaining > 0) {
            return Scaffold(
              backgroundColor: AppColors.background,
              body: ContinuePrompt(
                state: state,
                onContinue: (method) =>
                    context.read<GameBloc>().add(ContinueRequested(method)),
                onAcceptDefeat: () =>
                    context.read<GameBloc>().add(const AcceptDefeat()),
              ),
            );
          }
          return _GameOverScreen(state: state);
        }

        if (state is GameActive) {
          return _ActiveGameScreen(state: state);
        }

        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Active game
// ---------------------------------------------------------------------------

class _ActiveGameScreen extends StatelessWidget {
  final GameActive state;

  const _ActiveGameScreen({required this.state});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _GameHeader(state: state),
                TimerBar(
                  timeRemaining: state.turnTimeRemaining,
                  totalTime: state.mode == 'time_attack'
                      ? GameConstants.timeAttackTurnTimerSec
                      : GameConstants.classicTurnTimerSec,
                ),
                if (state.isMultiplayer) ...[
                  _TurnIndicator(state: state),
                  const SizedBox(height: 4),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: WordChainList(
                    words: state.wordChain,
                    scores: state.wordScores,
                    wordOwners: state.isMultiplayer ? state.wordOwners : null,
                    myPlayerId: state.myPlayerId,
                    opponentUsername: state.opponentUsername,
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      top: BorderSide(color: AppColors.divider, width: 1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      _NextLetterBar(state: state),
                      const SizedBox(height: 10),
                      WordInput(
                        startLetter: state.nextStartLetter,
                        enabled: state.isMyTurn && !state.opponentContinueWindowActive,
                        hintWord: state.hintWord,
                        onSubmit: (word) =>
                            context.read<GameBloc>().add(WordSubmitted(word)),
                      ),
                      const SizedBox(height: 12),
                      _PowerupRow(state: state),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Opponent continue-window overlay
        if (state.opponentContinueWindowActive)
          _OpponentContinueOverlay(
            remaining: state.opponentContinueWindowRemaining,
            opponentName: state.opponentUsername ?? 'Opponent',
          ),
        // Opponent disconnected banner
        if (state.opponentDisconnected)
          const _DisconnectedBanner(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Multiplayer header (names + scores)
// ---------------------------------------------------------------------------

class _GameHeader extends StatelessWidget {
  final GameActive state;

  const _GameHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isMultiplayer) {
      return _MultiplayerHeader(state: state);
    }
    return _SoloHeader(state: state);
  }
}

class _SoloHeader extends StatelessWidget {
  final GameActive state;

  const _SoloHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final headerLabel = switch (state.mode) {
      'time_attack' => 'SOLO · TIME ATTACK',
      'daily' => 'DAILY CHALLENGE',
      _ => '${state.opponentType == 'solo' ? 'SOLO' : 'VS AI'} · CLASSIC',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showEndGameDialog(context),
            child: const Icon(
              Icons.close,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            headerLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(
                    '${state.score}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (state.wordScores.isNotEmpty)
                    Text(
                      ' +${state.wordScores.last}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              Text(
                'CHAIN  ${state.wordChain.length}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEndGameDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('End Game?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Your current progress will be saved.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Playing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<GameBloc>().add(const GameEnded());
            },
            child: const Text(
              'End Game',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiplayerHeader extends StatelessWidget {
  final GameActive state;

  const _MultiplayerHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final modeLabel = state.mode == 'time_attack' ? 'TIME ATTACK' : 'CLASSIC';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Text(
            'MULTIPLAYER · $modeLabel',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _PlayerScoreChip(
                label: 'YOU',
                score: state.score,
                isActive: state.isMyTurn,
                align: CrossAxisAlignment.start,
              ),
              const Spacer(),
              Text(
                'CHAIN  ${state.wordChain.length}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              _PlayerScoreChip(
                label: state.opponentUsername?.toUpperCase() ?? 'OPP',
                score: state.opponentScore,
                isActive: !state.isMyTurn,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerScoreChip extends StatelessWidget {
  final String label;
  final int score;
  final bool isActive;
  final CrossAxisAlignment align;

  const _PlayerScoreChip({
    required this.label,
    required this.score,
    required this.isActive,
    required this.align,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.primary : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$score',
          style: TextStyle(
            color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Turn indicator
// ---------------------------------------------------------------------------

class _TurnIndicator extends StatelessWidget {
  final GameActive state;

  const _TurnIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      decoration: BoxDecoration(
        color: state.isMyTurn
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: state.isMyTurn ? AppColors.primary : AppColors.divider,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            state.isMyTurn ? Icons.edit_outlined : Icons.hourglass_empty,
            size: 14,
            color:
                state.isMyTurn ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            state.isMyTurn ? 'YOUR TURN' : 'OPPONENT\'S TURN',
            style: TextStyle(
              color:
                  state.isMyTurn ? AppColors.primary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Next letter bar + streak badge
// ---------------------------------------------------------------------------

class _NextLetterBar extends StatelessWidget {
  final GameActive state;

  const _NextLetterBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Text(
            'Next word starts with ',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (state.nextStartLetter != null)
            Text(
              state.nextStartLetter!.toUpperCase(),
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          const Spacer(),
          if (state.streak >= 2)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary, width: 1),
              ),
              child: Text(
                'STREAK ×${state.streak} 🔥',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Power-up row
// ---------------------------------------------------------------------------

class _PowerupRow extends StatelessWidget {
  final GameActive state;

  const _PowerupRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final isGuest = state.guestHintUsesLeft != 999;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _PowerupButton(
            emoji: '💡',
            label: isGuest ? '×${state.guestHintUsesLeft}' : '∞',
            enabled: !isGuest || state.guestHintUsesLeft > 0,
            onTap: () => context.read<GameBloc>().add(const HintRequested()),
          ),
          const SizedBox(width: 12),
          _PowerupButton(
            emoji: '⏱',
            label: '×0',
            enabled: false,
            onTap: null,
          ),
          const SizedBox(width: 12),
          _PowerupButton(
            emoji: '🛡',
            label: '×0',
            enabled: false,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _PowerupButton extends StatelessWidget {
  final String emoji;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _PowerupButton({
    required this.emoji,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? AppColors.divider
                : AppColors.divider.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: TextStyle(
                fontSize: 22,
                color: enabled ? null : Colors.white24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: enabled
                    ? AppColors.textSecondary
                    : AppColors.textSecondary.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
              if (isMultiplayer) ...[
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
                  onPressed: () => context.go('/home'),
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
                          opponentType: 'solo',
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
