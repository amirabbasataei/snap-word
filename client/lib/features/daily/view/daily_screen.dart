import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/daily/cubit/daily_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          DailyCubit(repository: getIt<DailyRepository>())..load(),
      child: const _DailyView(),
    );
  }
}

class _DailyView extends StatelessWidget {
  const _DailyView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DailyCubit, DailyState>(
      listenWhen: (prev, curr) => curr is DailyRetryAvailable,
      listener: (context, state) {
        if (state is DailyRetryAvailable) {
          context.push(
            '/game',
            extra: GameRouteArgs(
              mode: 'daily',
              opponentType: 'solo',
              startLetter: state.challenge.startLetter,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is DailyInitial || state is DailyLoading) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is DailyError) {
          return _ErrorView(
            message: state.message,
            onRetry: () => context.read<DailyCubit>().load(),
          );
        }
        if (state is DailyAvailable) {
          return _AvailableView(challenge: state.challenge);
        }
        if (state is DailyAttempted) {
          return _AttemptedView(challenge: state.challenge);
        }
        // DailyRetryAvailable: listener handles navigation; show spinner
        return const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Available view — challenge not yet attempted today
// ---------------------------------------------------------------------------

class _AvailableView extends StatelessWidget {
  final DailyChallenge challenge;

  const _AvailableView({required this.challenge});

  static const _months = [
    '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  String get _dateLabel {
    try {
      final d = DateTime.parse(challenge.challengeDate);
      return '${_months[d.month]} ${d.day}, ${d.year}';
    } catch (_) {
      return challenge.challengeDate.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              // Date + mode label
              Row(
                children: [
                  const Text('📅', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    'DAILY · $_dateLabel',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                'Challenge #${challenge.dayNumber}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'One attempt per day. Top score wins.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),

              // Challenge info card
              _ChallengeCard(challenge: challenge),

              const SizedBox(height: 20),

              // Rules
              _RulesList(canRetry: !challenge.hasRetried),

              const Spacer(),

              // Start button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text(
                    'START CHALLENGE',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  onPressed: () {
                    context.push(
                      '/game',
                      extra: GameRouteArgs(
                        mode: 'daily',
                        opponentType: 'solo',
                        startLetter: challenge.startLetter,
                      ),
                    );
                  },
                ),
              ),
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

class _ChallengeCard extends StatelessWidget {
  final DailyChallenge challenge;

  const _ChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Start letter display
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Start your chain with',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    challenge.startLetter.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Scores
              if (challenge.todaysBest > 0 || challenge.yourBest > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (challenge.todaysBest > 0) ...[
                      Text(
                        '${challenge.todaysBest}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Today\'s best',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (challenge.yourBest > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${challenge.yourBest}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        'Your best',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
          if (challenge.dailyStreak >= 3) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _StreakBadge(streak: challenge.dailyStreak),
            ),
          ],
        ],
      ),
    );
  }
}

class _RulesList extends StatelessWidget {
  final bool canRetry;

  const _RulesList({required this.canRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final rule in [
            'Up to ${GameConstants.dailyMaxWords} words — longest chain wins',
            '15 seconds per turn, first mistake ends the run',
            if (canRetry)
              'One retry available for ${GameConstants.dailyRetryCostCoins} 🪙 if you fail',
            'Share your result after — compare with friends!',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rule,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attempted view — result screen
// ---------------------------------------------------------------------------

class _AttemptedView extends StatelessWidget {
  final DailyChallenge challenge;

  const _AttemptedView({required this.challenge});

  DailyAttempt get _bestAttempt =>
      challenge.retryAttempt ?? challenge.attempt!;

  @override
  Widget build(BuildContext context) {
    final attempt = _bestAttempt;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => context.go('/home'),
        ),
        title: Text(
          'Daily #${challenge.dayNumber} — Done!',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            // Stats row
            Row(
              children: [
                _StatBox(
                  value: '${attempt.score}',
                  label: 'SCORE',
                ),
                const SizedBox(width: 10),
                _StatBox(
                  value: '${attempt.chainLength}',
                  label: 'WORDS',
                ),
                if (challenge.rank != null) ...[
                  const SizedBox(width: 10),
                  _StatBox(
                    value: '#${challenge.rank}',
                    label: 'RANK',
                  ),
                ],
              ],
            ),

            // Streak badge
            if (challenge.dailyStreak >= 1) ...[
              const SizedBox(height: 14),
              _StreakBadge(streak: challenge.dailyStreak),
            ],

            const SizedBox(height: 20),

            // Share card preview
            _ShareCardPreview(
              dayNumber: challenge.dayNumber,
              attempt: attempt,
            ),

            const SizedBox(height: 20),

            // Share button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('SHARE RESULT'),
                onPressed: () {
                  getIt<ShareService>().shareDaily(
                    DailyChallengeResult(
                      dayNumber: challenge.dayNumber,
                      score: attempt.score,
                      chainLength: attempt.chainLength,
                      wordChain: attempt.wordChain,
                    ),
                  );
                },
              ),
            ),

            // Retry button (only if first attempt and no retry yet)
            if (challenge.hasAttempted && !challenge.hasRetried) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    'RETRY  (${GameConstants.dailyRetryCostCoins} 🪙)',
                  ),
                  onPressed: () =>
                      context.read<DailyCubit>().retry(),
                ),
              ),
            ],

            // Retry attempt result (if both attempts done)
            if (challenge.hasRetried && challenge.attempt != null) ...[
              const SizedBox(height: 24),
              _RetryComparisonCard(
                first: challenge.attempt!,
                retry: challenge.retryAttempt!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;

  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
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
            const SizedBox(height: 2),
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
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final int streak;

  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            '$streak-day streak!',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareCardPreview extends StatelessWidget {
  final int dayNumber;
  final DailyAttempt attempt;

  const _ShareCardPreview({
    required this.dayNumber,
    required this.attempt,
  });

  @override
  Widget build(BuildContext context) {
    final chainText = attempt.wordChain
        .map((w) => w.toUpperCase())
        .join(' → ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'WordChain Daily #$dayNumber',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PREVIEW',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            chainText,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Score: ${attempt.score} · Play at wordchain.app',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryComparisonCard extends StatelessWidget {
  final DailyAttempt first;
  final DailyAttempt retry;

  const _RetryComparisonCard({required this.first, required this.retry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ATTEMPT COMPARISON',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CompareCell(label: '1st Attempt', score: first.score, words: first.chainLength),
              const SizedBox(width: 16),
              _CompareCell(label: 'Retry', score: retry.score, words: retry.chainLength),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompareCell extends StatelessWidget {
  final String label;
  final int score;
  final int words;

  const _CompareCell({
    required this.label,
    required this.score,
    required this.words,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$score',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$words words',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.textSecondary, size: 48),
              const SizedBox(height: 12),
              Text(
                message,
                style:
                    const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
