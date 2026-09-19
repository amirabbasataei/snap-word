import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/streak_strip.dart';
import 'package:wordchain/core/widgets/tint_chip.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/daily/cubit/daily_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';

// Persian week starts Saturday — same weekday-1 index StreakStrip uses,
// spelled out in full rather than initials.
const _weekdayNamesFull = [
  'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه',
];

String _mapDailyError(String code) {
  switch (code) {
    case 'no_daily_challenge':
      return 'چالش امروز هنوز آماده نشده';
    case 'not_attempted':
      return 'اول باید چالش امروز رو انجام بدی';
    case 'already_retried':
      return 'تلاش دوباره‌ی امروز رو قبلاً استفاده کردی';
    case 'insufficient_coins':
      return 'سکه‌ات برای تلاش دوباره کافی نیست';
    default:
      return 'مشکلی پیش آمد، دوباره تلاش کن';
  }
}

/// Weekday + Jalali day/month name, in Persian digits — matches the canvas
/// ("شنبه ۱۶ شهریور"). Weekday name keyed off the Gregorian `DateTime`
/// (day-of-week is identical between calendars); day/month converted via
/// `shamsi_date`.
String _headerSubtitle(String? challengeDateIso) {
  DateTime date;
  try {
    date = challengeDateIso != null && challengeDateIso.isNotEmpty
        ? DateTime.parse(challengeDateIso)
        : DateTime.now();
  } catch (_) {
    date = DateTime.now();
  }
  final weekday = _weekdayNamesFull[date.weekday - 1];
  final jalali = Jalali.fromDateTime(date);
  return '$weekday ${toPersianDigits(jalali.day)} ${jalali.formatter.mN}';
}

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
        final z = context.z;
        if (state is DailyInitial || state is DailyLoading) {
          return Scaffold(
            backgroundColor: z.paper,
            body: Center(child: CircularProgressIndicator(color: z.indigo)),
          );
        }
        if (state is DailyError) {
          return _ErrorView(
            message: _mapDailyError(state.code),
            onRetry: () => context.read<DailyCubit>().load(),
          );
        }
        if (state is DailyAvailable) {
          return _DailyBeforeView(challenge: state.challenge);
        }
        if (state is DailyAttempted) {
          return _DailyAfterView(challenge: state.challenge);
        }
        // DailyRetryAvailable: listener handles navigation; show spinner
        return Scaffold(
          backgroundColor: z.paper,
          body: Center(child: CircularProgressIndicator(color: z.indigo)),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ZDailyBefore — challenge not yet attempted today
// ---------------------------------------------------------------------------

class _DailyBeforeView extends StatefulWidget {
  final DailyChallenge challenge;

  const _DailyBeforeView({required this.challenge});

  @override
  State<_DailyBeforeView> createState() => _DailyBeforeViewState();
}

class _DailyBeforeViewState extends State<_DailyBeforeView> {
  DateTime? _lastPlayedDate;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await getIt<StatsDao>().getStats();
      if (mounted) setState(() => _lastPlayedDate = stats?.lastPlayedDate);
    } catch (_) {
      // Best-effort — the streak strip just hides until this resolves.
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final challenge = widget.challenge;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ZSpacing.screenGutter, ZSpacing.md, ZSpacing.screenGutter, ZSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackHeader(
                title: 'چالش روزانه',
                subtitle: _headerSubtitle(challenge.challengeDate),
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
              ),
              const SizedBox(height: ZSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SeedHero(challenge: challenge),
                      const SizedBox(height: ZSpacing.lg),
                      const _RulesCard(),
                      if (challenge.dailyStreak > 0) ...[
                        const SizedBox(height: ZSpacing.lg),
                        _StreakCard(
                          streakCount: challenge.dailyStreak,
                          lastPlayedDate: _lastPlayedDate,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: ZSpacing.md),
              _InkButton(
                label: 'شروع چالش امروز',
                onTap: () => context.push(
                  '/game',
                  extra: GameRouteArgs(
                    mode: 'daily',
                    opponentType: 'solo',
                    startLetter: challenge.startLetter,
                  ),
                ),
              ),
              const SizedBox(height: ZSpacing.sm),
              NeutralButton(
                label: 'دیدن جدول امروز',
                onPressed: () => context.push('/leaderboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeedHero extends StatelessWidget {
  final DailyChallenge challenge;

  const _SeedHero({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final subtitle = challenge.todaysBest > 0
        ? 'رکورد امروز ${toPersianDigits(challenge.todaysBest)} امتیاز'
        : 'اولین نفری باش که امروز بازی می‌کنه!';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.xl, vertical: ZSpacing.xxl),
      decoration: BoxDecoration(
        color: z.indigo,
        borderRadius: BorderRadius.circular(ZRadius.sheetMax),
        boxShadow: ZElevation.solidEdge(z.indigoDeep, depth: ZElevation.tileDepth),
      ),
      child: Column(
        children: [
          Text('حرف شروع امروز', style: ZTypography.metaLabel.copyWith(color: z.onIndigoSoft)),
          const SizedBox(height: ZSpacing.md),
          Container(
            width: ZTileSize.dailySeed,
            height: 106,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: z.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: ZElevation.solidEdge(z.line, depth: ZElevation.tileDepth),
            ),
            child: Text(
              challenge.startLetter,
              style: ZTypography.display.copyWith(color: z.indigo, fontSize: 60),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          Text('تا کجا می‌کشونیش؟',
              style: ZTypography.screenTitle.copyWith(color: z.onIndigo, fontSize: 20)),
          const SizedBox(height: 4),
          Text(subtitle, style: ZTypography.body.copyWith(color: z.onIndigoSoft, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final rows = [
      (
        toPersianDigits(GameConstants.soloLives),
        ZTint.coral,
        'با هر کلمهٔ اشتباه یک جان از دست می‌دهی.',
      ),
      (
        toPersianDigits(GameConstants.classicTurnTimerSec),
        ZTint.teal,
        'ثانیه برای هر نوبت؛ تکرار کلمه ممنوع.',
      ),
      (
        toPersianDigits(1),
        ZTint.indigo,
        'روزی یک بار؛ نتیجه در جدول روز ثبت می‌شود.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.xl),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border.all(color: z.line),
        borderRadius: BorderRadius.circular(ZRadius.sheetMin),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: z.line)),
              ),
              child: Row(
                children: [
                  _RuleBadge(text: rows[i].$1, tint: rows[i].$2),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Text(
                      rows[i].$3,
                      style: ZTypography.metaLabel.copyWith(color: z.ink60, fontSize: 12.5),
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

class _RuleBadge extends StatelessWidget {
  final String text;
  final ZTint tint;

  const _RuleBadge({required this.text, required this.tint});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (bg, fg) = switch (tint) {
      ZTint.indigo => (z.tintIndigo, z.indigo),
      ZTint.teal => (z.tintTeal, z.teal),
      ZTint.coral => (z.tintCoral, z.coral),
    };
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Text(
        text,
        style: ZTypography.cardTitle.copyWith(color: fg, fontSize: 14, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int streakCount;
  final DateTime? lastPlayedDate;
  final bool showTodayBadge;
  final int? recordDays;

  const _StreakCard({
    required this.streakCount,
    required this.lastPlayedDate,
    this.showTodayBadge = false,
    this.recordDays,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: ZSpacing.md),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border.all(color: z.line),
        borderRadius: BorderRadius.circular(ZRadius.sheetMin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${toPersianDigits(streakCount)} روز پیاپی',
                  style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 13.5)),
              if (showTodayBadge) ...[
                const SizedBox(width: ZSpacing.sm),
                const TintChip(label: '‎+۱ امروز', tint: ZTint.teal),
              ],
              const Spacer(),
              if (recordDays != null && recordDays! > 0)
                Text('رکورد: ${toPersianDigits(recordDays!)}',
                    style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: ZSpacing.md),
          StreakStrip(streakCount: streakCount, lastPlayedDate: lastPlayedDate),
        ],
      ),
    );
  }
}

class _InkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _InkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.ink,
          borderRadius: BorderRadius.circular(ZRadius.cardMin),
          boxShadow: ZElevation.solidEdge(z.inkSurfaceDeep, depth: ZElevation.buttonDepth),
        ),
        child: Text(label, style: ZTypography.button.copyWith(color: z.paper, fontSize: 17)),
      ),
    );
  }
}

class _BackHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BackHeader({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Row(
      children: [
        ZBackButton(onTap: onTap),
        const SizedBox(width: ZSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 18)),
            const SizedBox(height: 2),
            Text(subtitle, style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11.5)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ZDailyAfter — result screen
// ---------------------------------------------------------------------------

class _DailyAfterView extends StatefulWidget {
  final DailyChallenge challenge;

  const _DailyAfterView({required this.challenge});

  @override
  State<_DailyAfterView> createState() => _DailyAfterViewState();
}

class _DailyAfterViewState extends State<_DailyAfterView> {
  int _recordDays = 0;

  DailyAttempt get _bestAttempt =>
      widget.challenge.retryAttempt ?? widget.challenge.attempt!;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await getIt<StatsDao>().getStats();
      if (mounted) setState(() => _recordDays = stats?.longestDailyStreak ?? 0);
    } catch (_) {
      // Best-effort — the "رکورد" line just stays hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final challenge = widget.challenge;
    final attempt = _bestAttempt;
    final canRetry = challenge.hasAttempted && !challenge.hasRetried;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ZSpacing.screenGutter, ZSpacing.md, ZSpacing.screenGutter, ZSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackHeader(
                title: 'چالش امروز تمام شد',
                subtitle:
                    '${_headerSubtitle(challenge.challengeDate)} · حرف شروع «${challenge.startLetter}»',
                onTap: () => context.go('/home'),
              ),
              const SizedBox(height: ZSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ResultHero(attempt: attempt, rank: challenge.rank),
                      const SizedBox(height: ZSpacing.lg),
                      _ChainChipsCard(wordChain: attempt.wordChain),
                      if (challenge.dailyStreak > 0) ...[
                        const SizedBox(height: ZSpacing.lg),
                        _StreakCard(
                          streakCount: challenge.dailyStreak,
                          lastPlayedDate: DateTime.now(),
                          showTodayBadge: true,
                          recordDays: _recordDays,
                        ),
                      ],
                      const SizedBox(height: ZSpacing.lg),
                      const _NextChallengeRow(),
                      if (challenge.hasRetried && challenge.attempt != null) ...[
                        const SizedBox(height: ZSpacing.lg),
                        _RetryComparisonCard(
                          first: challenge.attempt!,
                          retry: challenge.retryAttempt!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: ZSpacing.md),
              AccentButton(
                accent: ZAccentColor.coral,
                label: 'هم‌رسانی نتیجه',
                onPressed: () => getIt<ShareService>().shareDaily(
                  DailyChallengeResult(
                    dayNumber: challenge.dayNumber,
                    score: attempt.score,
                    chainLength: attempt.chainLength,
                    wordChain: attempt.wordChain,
                  ),
                ),
              ),
              const SizedBox(height: ZSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: NeutralButton(
                      label: 'جدول امروز',
                      onPressed: () => context.push('/leaderboard'),
                    ),
                  ),
                  const SizedBox(width: ZSpacing.sm),
                  Expanded(
                    child: NeutralButton(
                      label: 'بازی تک‌نفره',
                      onPressed: () => context.push(
                        '/game',
                        extra: const GameRouteArgs(mode: 'classic', opponentType: 'solo'),
                      ),
                    ),
                  ),
                ],
              ),
              if (canRetry) ...[
                const SizedBox(height: ZSpacing.sm),
                NeutralButton(
                  label: 'امتحان دوباره (${toPersianDigits(GameConstants.dailyRetryCostCoins)} 🪙)',
                  onPressed: () => context.read<DailyCubit>().retry(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultHero extends StatelessWidget {
  final DailyAttempt attempt;
  final int? rank;

  const _ResultHero({required this.attempt, required this.rank});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZSpacing.xl),
      decoration: BoxDecoration(
        color: z.teal,
        borderRadius: BorderRadius.circular(ZRadius.sheetMax),
        boxShadow: ZElevation.solidEdge(z.tealDeep, depth: ZElevation.tileDepth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('زنجیر تو', style: ZTypography.metaLabel.copyWith(color: z.onTealSoft)),
              const SizedBox(height: 4),
              Text(toPersianDigits(attempt.chainLength),
                  style: ZTypography.display.copyWith(color: z.onTeal, fontSize: 44)),
              Text('کلمه', style: ZTypography.cardTitle.copyWith(color: z.onTealSoft, fontSize: 12)),
            ],
          ),
          const SizedBox(width: ZSpacing.lg),
          Container(width: 1, height: 66, color: z.onTealSoft.withValues(alpha: .35)),
          const SizedBox(width: ZSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rank != null ? 'رتبهٔ ${toPersianDigits(rank!)} امروز' : 'نتیجهٔ امروزت ثبت شد',
                  style: ZTypography.cardTitle.copyWith(color: z.onTeal, fontSize: 17),
                ),
                const SizedBox(height: ZSpacing.sm),
                Text('${toPersianDigits(attempt.score)} امتیاز',
                    style: ZTypography.body.copyWith(color: z.onTealSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainChipsCard extends StatelessWidget {
  final List<String> wordChain;

  const _ChainChipsCard({required this.wordChain});

  static const _shownLimit = 8;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    if (wordChain.isEmpty) return const SizedBox.shrink();

    final visible = wordChain.length > _shownLimit ? wordChain.sublist(0, _shownLimit) : wordChain;
    final remaining = wordChain.length - visible.length;
    // Longest among the *visible* chips only — the true longest word can
    // fall in the "+N دیگر" overflow, where highlighting it would show no
    // visible effect at all.
    final longest = visible.reduce((a, b) => a.length >= b.length ? a : b);

    return SolidCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('زنجیر امروزت', style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11)),
          const SizedBox(height: ZSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in visible)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: w == longest ? z.indigo : z.paper,
                    borderRadius: BorderRadius.circular(ZRadius.chip),
                  ),
                  child: Text(
                    w,
                    style: ZTypography.metaLabel.copyWith(
                      color: w == longest ? z.onIndigo : z.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              if (remaining > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(color: z.paper, borderRadius: BorderRadius.circular(ZRadius.chip)),
                  child: Text(
                    '‎+${toPersianDigits(remaining)} دیگر',
                    style: ZTypography.metaLabel.copyWith(color: z.ink40, fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextChallengeRow extends StatefulWidget {
  const _NextChallengeRow();

  @override
  State<_NextChallengeRow> createState() => _NextChallengeRowState();
}

class _NextChallengeRowState extends State<_NextChallengeRow> {
  late final Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now().toUtc();
    final nextMidnight = DateTime.utc(now.year, now.month, now.day + 1);
    final remaining = nextMidnight.difference(now);
    if (mounted) setState(() => _remaining = remaining);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _label {
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return toPersianDigits('$h:$m:$s');
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: ZSpacing.md),
      decoration: BoxDecoration(color: z.inkSurface, borderRadius: BorderRadius.circular(ZRadius.cardMax)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('چالش بعدی', style: ZTypography.cardTitle.copyWith(color: z.onInkSurface, fontSize: 13)),
                Text('فردا ساعت ۰۰:۰۰ با حرف تازه',
                    style: ZTypography.metaLabel.copyWith(color: z.onInkSurfaceSoft, fontSize: 11.5)),
              ],
            ),
          ),
          Text(_label,
              style: ZTypography.cardTitle.copyWith(color: z.onInkSurface, fontSize: 20, fontWeight: FontWeight.w900)),
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
    final z = context.z;
    return SolidCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('مقایسهٔ دو تلاش', style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11)),
          const SizedBox(height: ZSpacing.md),
          Row(
            children: [
              _CompareCell(label: 'تلاش اول', score: first.score, words: first.chainLength),
              const SizedBox(width: ZSpacing.lg),
              _CompareCell(label: 'تلاش دوباره', score: retry.score, words: retry.chainLength),
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

  const _CompareCell({required this.label, required this.score, required this.words});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ZTypography.metaLabel.copyWith(color: z.ink60, fontSize: 11.5)),
          const SizedBox(height: 4),
          Text(toPersianDigits(score),
              style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 19, fontWeight: FontWeight.w900)),
          Text('${toPersianDigits(words)} کلمه',
              style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11.5)),
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
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZSpacing.xl),
          child: Column(
            children: [
              ZBackButton(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: z.ink40, size: 44),
                      const SizedBox(height: ZSpacing.md),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: ZTypography.body.copyWith(color: z.ink60),
                      ),
                      const SizedBox(height: ZSpacing.xl),
                      NeutralButton(label: 'تلاش دوباره', onPressed: onRetry),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
