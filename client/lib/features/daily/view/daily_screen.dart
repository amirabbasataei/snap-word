import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/insufficient_coins_dialog.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_state_card.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/daily/cubit/daily_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/daily/view/widgets/daily_actions.dart';
import 'package:wordchain/features/daily/view/widgets/daily_chain_card.dart';
import 'package:wordchain/features/daily/view/widgets/daily_compare_card.dart';
import 'package:wordchain/features/daily/view/widgets/daily_format.dart';
import 'package:wordchain/features/daily/view/widgets/daily_letter_hero.dart';
import 'package:wordchain/features/daily/view/widgets/daily_parts.dart';
import 'package:wordchain/features/daily/view/widgets/daily_result_hero.dart';
import 'package:wordchain/features/daily/view/widgets/daily_rules.dart';
import 'package:wordchain/features/daily/view/widgets/daily_streak.dart';
import 'package:wordchain/features/daily/view/widgets/daily_tiles.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

/// «چالش روزانه» — the Daily Challenge, "A · mascot-led" (canvas
/// `ZDailyBeforeA` before the game, `ZDailyAfterA` after it).
///
/// A pushed route (not a tab): `/daily` is guest-gated by the router, which
/// sends a signed-out player to `/login?return=/daily`. Both states are scroll
/// views on the sky scene; the start button is pinned under the pre-game one.
/// The clocks (date, time to the next challenge) are read when the screen
/// builds — nothing ticks; coming back from the background across Iran
/// midnight reloads the day ([DailyCubit.refreshIfStale]).
class DailyScreen extends StatelessWidget {
  /// Clock for the countdown and the week strip; tests pass a fixed one.
  final DateTime Function()? clock;

  const DailyScreen({super.key, this.clock});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DailyCubit(repository: getIt<DailyRepository>())..load(),
      child: _DailyView(clock: clock),
    );
  }
}

class _DailyView extends StatefulWidget {
  final DateTime Function()? clock;

  const _DailyView({required this.clock});

  @override
  State<_DailyView> createState() => _DailyViewState();
}

class _DailyViewState extends State<_DailyView> with WidgetsBindingObserver {
  DateTime? _lastPlayed;
  int _record = 0;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<DailyCubit>().refreshIfStale(_now());
    }
  }

  /// The device's own streak facts (local Drift stats) — best effort: the
  /// «رکورد» line and the strip's played days just stay empty without them.
  Future<void> _loadStats() async {
    try {
      final stats = await getIt<StatsDao>().getStats();
      if (!mounted) return;
      setState(() {
        _lastPlayed = stats?.lastPlayedDate;
        _record = stats?.longestDailyStreak ?? 0;
      });
    } catch (_) {}
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DailyCubit, DailyState>(
      listenWhen:
          (prev, curr) =>
              curr is DailyRetryAvailable ||
              curr is DailyInsufficientCoins ||
              curr is DailyRetryFailed,
      listener: (context, state) {
        switch (state) {
          case DailyInsufficientCoins():
            showInsufficientCoinsDialog(
              context,
              cost: GameConstants.dailyRetryCostCoins,
            );
          case DailyRetryFailed(:final message):
            ZToast.show(context, message, kind: ZToastKind.error);
          case DailyRetryAvailable(:final challenge):
            context.push(
              '/game',
              extra: GameRouteArgs(
                mode: 'daily',
                opponentType: 'solo',
                startLetter: challenge.startLetter,
              ),
            );
          default:
        }
      },
      builder: (context, state) {
        return switch (state) {
          DailyAvailable(:final challenge) => _DailyBefore(
            challenge: challenge,
            now: _now(),
            lastPlayed: _lastPlayed,
            record: _record,
            onBack: _back,
          ),
          DailyAttempted(:final challenge) => _after(challenge, state),
          DailyRetryAvailable(:final challenge) => _after(challenge, state),
          DailyError(:final message) => _Frame(
            onBack: _back,
            child: ZStateCard(
              child: ZLoadState.error(
                message: message,
                onRetry: () => context.read<DailyCubit>().load(),
              ),
            ),
          ),
          _ => _Frame(
            onBack: _back,
            child: const ZStateCard(child: ZLoadState.loading()),
          ),
        };
      },
    );
  }

  Widget _after(DailyChallenge challenge, DailyState state) => _DailyAfter(
    challenge: challenge,
    now: _now(),
    record: _record,
    retrying: state is DailyAttempted && state.retrying,
    onBack: () => context.go('/home'),
  );
}

/// Scene, header and a body slot for the states with no challenge to show.
class _Frame extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;

  const _Frame({required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    return _Scaffold(
      header: DailyHeader(title: 'چالش روزانه', onBack: onBack),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: child,
      ),
    );
  }
}

class _Scaffold extends StatelessWidget {
  final Widget header;
  final Widget body;
  final Widget? footer;

  const _Scaffold({required this.header, required this.body, this.footer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zs.sky3,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeSceneBackground(),
          SafeArea(
            child: Column(
              children: [
                header,
                Expanded(child: body),
                if (footer != null) footer!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ZDailyBefore — today's challenge not played yet
// ---------------------------------------------------------------------------

class _DailyBefore extends StatelessWidget {
  final DailyChallenge challenge;
  final DateTime now;
  final DateTime? lastPlayed;
  final int record;
  final VoidCallback onBack;

  const _DailyBefore({
    required this.challenge,
    required this.now,
    required this.lastPlayed,
    required this.record,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    // Real facts only: «N نفر امروز بازی کردند · میانگین …» needs a player
    // count and an average the server does not send (todo.md 2.5), so the
    // chip shows the day's best score, or invites the first player.
    final best = challenge.todaysBest;
    return _Scaffold(
      header: DailyHeader(
        title: 'چالش روزانه',
        onBack: onBack,
        dateLabel: dailyDateLabel(challenge.challengeDate, now),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            DailyLetterHero(letter: challenge.startLetter),
            ZOverEnter(
              kind: ZOverEnterKind.up,
              delayMs: 500,
              child: DailyPill(
                best > 0
                    ? 'رکورد امروز ${formatPersianNumber(best)} امتیاز'
                    : 'اولین نفری باش که امروز بازی می‌کنه!',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ZOverEnter(
                kind: ZOverEnterKind.up,
                delayMs: 580,
                child: const DailyRules(),
              ),
            ),
            if (challenge.dailyStreak > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: ZOverEnter(
                  kind: ZOverEnterKind.up,
                  delayMs: 650,
                  child: DailyStreakCard(
                    streak: challenge.dailyStreak,
                    record: record,
                    lastPlayed: lastPlayed,
                    today: now.toUtc().add(iranOffset),
                  ),
                ),
              ),
          ],
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: ZOverEnter(
          kind: ZOverEnterKind.up,
          delayMs: 720,
          child: DailyBeforeActions(
            onStart:
                () => context.push(
                  '/game',
                  extra: GameRouteArgs(
                    mode: 'daily',
                    opponentType: 'solo',
                    startLetter: challenge.startLetter,
                  ),
                ),
            onBoard: () => context.push('/daily/board'),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ZDailyAfter — the result
// ---------------------------------------------------------------------------

class _DailyAfter extends StatelessWidget {
  final DailyChallenge challenge;
  final DateTime now;
  final int record;
  final bool retrying;
  final VoidCallback onBack;

  const _DailyAfter({
    required this.challenge,
    required this.now,
    required this.record,
    required this.retrying,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final attempt = challenge.bestAttempt!;
    return _Scaffold(
      header: DailyHeader(title: 'چالش امروز تمام شد', onBack: onBack),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          children: [
            const SizedBox(height: 10),
            ZOverEnter(
              kind: ZOverEnterKind.up,
              delayMs: 60,
              child: DailyPill(
                '${dailyDateLabel(challenge.challengeDate, now)} · '
                'حرف شروع «${challenge.startLetter}»',
              ),
            ),
            DailyResultHero(
              words: attempt.chainLength,
              score: attempt.score,
              rank: challenge.rank,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ZOverEnter(
                kind: ZOverEnterKind.up,
                delayMs: 600,
                child: DailyChainCard(words: attempt.wordChain),
              ),
            ),
            if (challenge.hasRetried)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: DailyCompareCard(
                  first: challenge.attempt!,
                  retry: challenge.retryAttempt!,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ZOverEnter(
                kind: ZOverEnterKind.up,
                delayMs: 680,
                child: DailyInfoTiles(
                  streak: challenge.dailyStreak,
                  record: record,
                  now: now,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: ZOverEnter(
                kind: ZOverEnterKind.up,
                delayMs: 760,
                child: DailyAfterActions(
                  retrying: retrying,
                  onShare:
                      () => getIt<ShareService>().shareDaily(
                        DailyChallengeResult(
                          dayNumber: challenge.dayNumber,
                          score: attempt.score,
                          chainLength: attempt.chainLength,
                          wordChain: attempt.wordChain,
                        ),
                      ),
                  onBoard: () => context.push('/daily/board'),
                  onSolo:
                      () => context.push(
                        '/game',
                        extra: const GameRouteArgs(
                          mode: 'classic',
                          opponentType: 'solo',
                        ),
                      ),
                  onRetry:
                      challenge.canRetry
                          ? () => context.read<DailyCubit>().retry()
                          : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
