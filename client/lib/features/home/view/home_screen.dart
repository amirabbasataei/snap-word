import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/theme/theme_cubit.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/coin_pill.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/tint_chip.dart';
import 'package:wordchain/core/widgets/streak_strip.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LocalMatche? _activeMatch;
  LocalPlayerStat? _stats;
  bool _checked = false;

  int _coins = 0;
  DailyChallenge? _daily;
  int? _weeklyRank;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final match = await getIt<MatchDao>().getActiveMatch();
    final stats = await getIt<StatsDao>().getStats();
    if (mounted) {
      setState(() {
        _activeMatch = match;
        _stats = stats;
        _checked = true;
      });
    }

    if (_isAuthenticated) {
      _fetchCoins();
      _fetchDailyChallenge();
      _fetchWeeklyRank();
    }
  }

  Future<void> _fetchCoins() async {
    try {
      final stats = await getIt<ProfileRepository>().fetchStats();
      if (mounted) setState(() => _coins = stats.coins);
    } catch (_) {
      // Best-effort — home screen still renders without a live coin count.
    }
  }

  Future<void> _fetchDailyChallenge() async {
    try {
      final daily = await getIt<DailyRepository>().getDailyChallenge();
      if (mounted) setState(() => _daily = daily);
    } catch (_) {
      // Best-effort — hero falls back to the generic countdown-only state.
    }
  }

  Future<void> _fetchWeeklyRank() async {
    try {
      final result = await getIt<LeaderboardRepository>().fetchGlobal();
      if (mounted && result.playerRank > 0) {
        setState(() => _weeklyRank = result.playerRank);
      }
    } catch (_) {
      // Best-effort — teaser row stays hidden without a rank.
    }
  }

  bool get _isAuthenticated => getIt<AuthCubit>().state is AuthAuthenticated;

  int get _hoursUntilNextDaily {
    final now = DateTime.now().toUtc();
    final nextMidnight = DateTime.utc(now.year, now.month, now.day + 1);
    return nextMidnight.difference(now).inHours;
  }

  void _startSolo(BuildContext context) {
    _showModeSheet(context, title: 'تک‌نفره', opponentType: 'solo');
  }

  void _startVsAi(BuildContext context) {
    _showDifficultySheet(context);
  }

  void _startOnline(BuildContext context) {
    if (!_isAuthenticated) {
      context.push('/login?return=/lobby');
    } else {
      context.push('/lobby');
    }
  }

  void _showModeSheet(
    BuildContext context, {
    required String title,
    required String opponentType,
  }) {
    final z = context.z;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: z.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZRadius.sheetMax),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: ZTypography.screenTitle.copyWith(color: z.ink)),
              const SizedBox(height: ZSpacing.xxl),
              AccentButton(
                label: 'کلاسیک (۱۵ ثانیه هر نوبت)',
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/game',
                    extra: GameRouteArgs(mode: 'classic', opponentType: opponentType),
                  );
                },
              ),
              const SizedBox(height: ZSpacing.md),
              NeutralButton(
                label: 'زمان‌دار (۸ ثانیه · ۹۰ ثانیه کل)',
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/game',
                    extra: GameRouteArgs(mode: 'time_attack', opponentType: opponentType),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDifficultySheet(BuildContext context) {
    final z = context.z;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: z.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZRadius.sheetMax),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('حریف هوشمند — انتخاب سطح',
                  style: ZTypography.screenTitle.copyWith(color: z.ink)),
              const SizedBox(height: ZSpacing.xxl),
              for (final entry in [
                ('آسان', 'ai_easy', 'اشتباه زیاد، پاسخ کند', ZAccent.teal),
                ('متوسط', 'ai_medium', 'چالش متعادل', ZAccent.amber),
                ('سخت', 'ai_hard', 'سریع و با کلمات تله', ZAccent.coral),
              ]) ...[
                _DifficultyTile(
                  label: entry.$1,
                  subtitle: entry.$3,
                  accent: entry.$4,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showModeSheet(
                      context,
                      title: 'حریف هوشمند — ${entry.$1}',
                      opponentType: entry.$2,
                    );
                  },
                ),
                const SizedBox(height: ZSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final dailyStreak = _stats?.dailyStreak ?? 0;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            ZSpacing.screenGutter,
            ZSpacing.lg,
            ZSpacing.screenGutter,
            ZSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(coins: _coins),
              const SizedBox(height: ZSpacing.xxl),
              const _Wordmark(),
              const SizedBox(height: ZSpacing.xxl),
              if (_checked && dailyStreak > 0) ...[
                _StreakCard(
                  streakCount: dailyStreak,
                  bestStreak: _stats?.longestDailyStreak ?? 0,
                  lastPlayedDate: _stats?.lastPlayedDate,
                ),
                const SizedBox(height: ZSpacing.md),
              ],
              _ModeGrid(
                showDaily: _isAuthenticated,
                daily: _daily,
                hoursUntilNextDaily: _hoursUntilNextDaily,
                onDaily: () => context.push('/daily'),
                onSolo: () => _startSolo(context),
                onVsAi: () => _startVsAi(context),
                onOnline: () => _startOnline(context),
              ),
              const SizedBox(height: ZSpacing.md),
              if (_isAuthenticated)
                _WeeklyRankTeaser(
                  rank: _weeklyRank,
                  onTap: () => context.go('/leaderboard'),
                ),
              if (_checked && _activeMatch != null) ...[
                const SizedBox(height: ZSpacing.md),
                _ResumeCard(
                  match: _activeMatch!,
                  onTap: () {
                    final match = _activeMatch!;
                    context.push(
                      '/game',
                      extra: GameRouteArgs(
                        mode: match.mode,
                        opponentType: match.opponentType,
                        resumeMatchId: match.id,
                      ),
                    );
                  },
                ),
              ],
              if (_checked && !_isAuthenticated) ...[
                const SizedBox(height: ZSpacing.md),
                _GuestBanner(onTap: () => context.push('/login')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — coin pill + two icon buttons
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final int coins;

  const _TopBar({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CoinPill(amount: coins),
        const Spacer(),
        // Temporary QA affordance: toggles light/dark until ZProfile ships
        // the real حالت شب switch (Stage 5). Remove once that toggle lands.
        _IconSquare(
          icon: Icons.dark_mode_outlined,
          onTap: () => getIt<ThemeCubit>().toggle(),
        ),
        const SizedBox(width: ZSpacing.sm),
        const _IconSquare(icon: Icons.notifications_none_rounded),
      ],
    );
  }
}

class _IconSquare extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _IconSquare({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.surface,
          border: Border.all(color: z.line),
          borderRadius: BorderRadius.circular(ZRadius.tileMax),
        ),
        child: Icon(icon, size: 18, color: z.ink40),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wordmark — 5 rotated letter tiles
// ---------------------------------------------------------------------------

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  static double _deg(double degrees) => degrees * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    const letters = [
      ('ز', ZAccent.indigo, -5.0),
      ('ن', ZAccent.teal, 2.0),
      ('ج', ZAccent.amber, -2.0),
      ('ی', ZAccent.coral, 4.0),
      ('ر', ZAccent.indigo, -3.0),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            for (final entry in letters) ...[
              LetterTile(
                letter: entry.$1,
                accent: entry.$2,
                size: 38,
                height: 48,
                radius: ZRadius.tileMax,
                fontSize: 24,
                rotation: _deg(entry.$3),
              ),
              if (entry != letters.last) const SizedBox(width: 5),
            ],
          ],
        ),
        const SizedBox(width: ZSpacing.md),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'زنجیر',
                style: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  height: 1.1,
                  letterSpacing: -0.5,
                  color: z.ink,
                ),
              ),
              Text(
                'حرف آخر، حرف اول!',
                style: ZTypography.metaLabel.copyWith(color: z.ink60, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Streak card
// ---------------------------------------------------------------------------

class _StreakCard extends StatelessWidget {
  final int streakCount;
  final int bestStreak;
  final DateTime? lastPlayedDate;

  const _StreakCard({
    required this.streakCount,
    required this.bestStreak,
    required this.lastPlayedDate,
  });

  bool get _playedToday {
    if (lastPlayedDate == null) return false;
    final now = DateTime.now();
    return lastPlayedDate!.year == now.year &&
        lastPlayedDate!.month == now.month &&
        lastPlayedDate!.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SolidCard(
      elevated: false,
      radius: ZRadius.cardMax,
      // 16px horizontal / 14px vertical — the design's card padding here
      // doesn't land on a named ZSpacing step.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: ZSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${formatPersianNumber(streakCount)} روز پیاپی',
                style: ZTypography.cardTitle.copyWith(color: z.ink),
              ),
              const SizedBox(width: ZSpacing.sm),
              if (!_playedToday) const TintChip(label: 'امروز هم بزن!', tint: ZTint.coral),
              const Spacer(),
              Text(
                'رکورد: ${formatPersianNumber(bestStreak)}',
                style: ZTypography.metaLabel.copyWith(color: z.ink40),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.md),
          StreakStrip(streakCount: streakCount, lastPlayedDate: lastPlayedDate),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode grid — daily hero (indigo) + solo / vs-ai + online
// ---------------------------------------------------------------------------

class _ModeGrid extends StatelessWidget {
  final bool showDaily;
  final DailyChallenge? daily;
  final int hoursUntilNextDaily;
  final VoidCallback onDaily;
  final VoidCallback onSolo;
  final VoidCallback onVsAi;
  final VoidCallback onOnline;

  const _ModeGrid({
    required this.showDaily,
    required this.daily,
    required this.hoursUntilNextDaily,
    required this.onDaily,
    required this.onSolo,
    required this.onVsAi,
    required this.onOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDaily) ...[
          _DailyHero(
            daily: daily,
            hoursLeft: hoursUntilNextDaily,
            onTap: onDaily,
          ),
          const SizedBox(height: ZSpacing.md),
        ],
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ModeCard(
                  label: '۱',
                  accent: ZAccent.teal,
                  title: 'تک‌نفره',
                  subtitle: 'بی‌وقفه تا آخرین کلمه',
                  onTap: onSolo,
                ),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: _ModeCard(
                  label: 'ه',
                  accent: ZAccent.amber,
                  title: 'حریف هوشمند',
                  subtitle: 'سه سطح؛ آخری بی‌رحم است',
                  onTap: onVsAi,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.md),
        _OnlineCard(onTap: onOnline),
      ],
    );
  }
}

class _DailyHero extends StatelessWidget {
  final DailyChallenge? daily;
  final int hoursLeft;
  final VoidCallback onTap;

  const _DailyHero({required this.daily, required this.hoursLeft, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final letter = daily?.startLetter.toUpperCase();
    final subtitle = daily == null
        ? '${formatPersianNumber(hoursLeft)} ساعت مانده'
        : '${formatPersianNumber(hoursLeft)} ساعت مانده · رکورد امروز ${formatPersianNumber(daily!.todaysBest)}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ZSpacing.xl, vertical: ZSpacing.xxl),
        decoration: BoxDecoration(
          color: z.indigo,
          borderRadius: BorderRadius.circular(ZRadius.cardMax),
          boxShadow: ZElevation.solidEdge(z.indigoDeep, depth: ZElevation.tileDepth),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'چالش روزانه',
                    style: ZTypography.metaLabel.copyWith(color: z.onIndigoSoft),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'زنجیر امروز',
                    style: ZTypography.screenTitle.copyWith(color: z.onIndigo, fontSize: 21),
                  ),
                  Text(
                    subtitle,
                    style: ZTypography.body.copyWith(color: z.onIndigoSoft, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ZSpacing.md),
            Container(
              width: 60,
              height: 66,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: z.surface,
                borderRadius: BorderRadius.circular(14),
                // rgba(0,0,0,.2) in the design — a fixed neutral drop shadow,
                // not a token, same in both themes.
                boxShadow: const [BoxShadow(color: Color(0x33000000), offset: Offset(0, 4))],
              ),
              child: Text(
                letter ?? '؟',
                style: ZTypography.display.copyWith(color: z.indigo, fontSize: 34),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String label;
  final ZAccent accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.label,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: SolidCard(
        radius: ZRadius.cardMax,
        padding: const EdgeInsets.all(ZSpacing.lg + 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LetterTile(letter: label, accent: accent, size: ZTileSize.prompt),
            const SizedBox(height: ZSpacing.md),
            Text(title, style: ZTypography.cardTitle.copyWith(color: z.ink)),
            Text(
              subtitle,
              style: ZTypography.body.copyWith(color: z.ink60, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineCard extends StatelessWidget {
  final VoidCallback onTap;

  const _OnlineCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: SolidCard(
        radius: ZRadius.cardMax,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: ZSpacing.lg),
        child: Row(
          children: [
            const LetterTile(letter: '۲', accent: ZAccent.coral, size: ZTileSize.prompt),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رویارویی آنلاین', style: ZTypography.cardTitle.copyWith(color: z.ink)),
                  Text(
                    'با بازیکنان دیگر به رقابت بپرداز',
                    style: ZTypography.body.copyWith(color: z.ink60, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            TintChip(label: 'شروع', tint: ZTint.coral),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly rank teaser
// ---------------------------------------------------------------------------

class _WeeklyRankTeaser extends StatelessWidget {
  final int? rank;
  final VoidCallback onTap;

  const _WeeklyRankTeaser({required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final subtitle = rank == null
        ? 'برای دیدن رتبه‌ات یک بازی آنلاین انجام بده'
        : rank! <= 10
            ? 'تو نفر ${formatPersianNumber(rank!)}اُمی؛ در ده‌تای اول!'
            : 'تو نفر ${formatPersianNumber(rank!)}اُمی؛ ${formatPersianNumber(rank! - 10)} پله تا ده‌تای اول';

    return GestureDetector(
      onTap: onTap,
      child: SolidCard(
        radius: ZRadius.cardMax,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: ZSpacing.md + 1),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 28,
              child: Stack(
                children: [
                  _RankDot(color: z.indigo, offset: 0),
                  _RankDot(color: z.teal, offset: 1, border: z.surface),
                  _RankDot(color: z.amber, offset: 2, border: z.surface),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('جدول هفته', style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 13.5)),
                  Text(subtitle, style: ZTypography.body.copyWith(color: z.ink60, fontSize: 11.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_left, color: z.ink60, size: 18),
          ],
        ),
      ),
    );
  }
}

class _RankDot extends StatelessWidget {
  final Color color;
  final int offset;
  final Color? border;

  const _RankDot({required this.color, required this.offset, this.border});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: offset * 19.0,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border != null ? Border.all(color: border!, width: 2) : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resume card
// ---------------------------------------------------------------------------

class _ResumeCard extends StatelessWidget {
  final LocalMatche match;
  final VoidCallback onTap;

  const _ResumeCard({required this.match, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: SolidCard(
        radius: ZRadius.cardMax,
        color: z.tintIndigo,
        padding: const EdgeInsets.all(ZSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.play_circle_fill, color: z.indigo, size: 28),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ادامهٔ بازی', style: ZTypography.cardTitle.copyWith(color: z.ink)),
                  Text(
                    '${match.mode == 'time_attack' ? 'زمان‌دار' : 'کلاسیک'} · ${match.opponentType == 'solo' ? 'تک‌نفره' : 'حریف هوشمند'}',
                    style: ZTypography.body.copyWith(color: z.ink60, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left, color: z.indigo),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guest upsell banner
// ---------------------------------------------------------------------------

class _GuestBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _GuestBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: SolidCard(
        radius: ZRadius.cardMax,
        padding: const EdgeInsets.all(ZSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: z.ink60, size: 20),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Text(
                'رایگان ثبت‌نام کن تا پیشرفتت ذخیره شود و به رویارویی آنلاین و جدول امتیازات دسترسی پیدا کنی.',
                style: ZTypography.body.copyWith(color: z.ink60),
              ),
            ),
            const SizedBox(width: ZSpacing.sm),
            Icon(Icons.chevron_left, color: z.ink60),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Difficulty tile (bottom sheet row)
// ---------------------------------------------------------------------------

class _DifficultyTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final ZAccent accent;
  final VoidCallback onTap;

  const _DifficultyTile({
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: SolidCard(
        elevated: false,
        padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: ZSpacing.md),
        child: Row(
          children: [
            LetterTile(letter: label[0], accent: accent, size: ZTileSize.prompt),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: ZTypography.cardTitle.copyWith(color: z.ink)),
                  Text(subtitle, style: ZTypography.body.copyWith(color: z.ink60, fontSize: 11.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_left, color: z.ink40),
          ],
        ),
      ),
    );
  }
}
