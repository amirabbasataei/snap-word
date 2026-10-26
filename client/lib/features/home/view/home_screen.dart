import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/theme_cubit.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/home/view/widgets/home_level_dialog.dart';
import 'package:wordchain/features/home/view/widgets/home_view.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';
import 'package:wordchain/features/rewards/cubit/rewards_cubit.dart';

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
  int _level = 1;
  int _xpInLevel = 0;
  int _xpForNext = 1000;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<int>? _tabSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Home lives inside `_MainShell`'s `StatefulShellRoute.indexedStack`
    // (`app_router.dart`), which keeps every branch's widget alive forever —
    // switching tabs never rebuilds it. Without this, signing in or out
    // from another screen (e.g. ZLogin, ZProfile's sign-out) never
    // refreshed Home's coin pill / daily hero / weekly-rank teaser, exactly
    // the same reactivity gap already found and fixed on ZProfile/ZFriends/
    // ZBoard (those use `BlocBuilder<AuthCubit>`; Home is a plain
    // `StatefulWidget` with local fetch state, so it listens to the stream
    // directly instead).
    _authSub = getIt<AuthCubit>().stream.listen((_) => _loadData());
    _tabSub = getIt<TabRefreshBus>().stream.listen((i) {
      if (i == MainTab.home) _loadData();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _tabSub?.cancel();
    super.dispose();
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
      _updateCoinsFromAuth();
      getIt<RewardsCubit>().refresh();
      getIt<MessagesCubit>().refresh();
      _fetchDailyChallenge();
      _fetchLevel();
    } else if (mounted) {
      setState(() {
        _coins = 0;
        _daily = null;
        // Guests have no server-side XP: show the level-1 default.
        _level = 1;
        _xpInLevel = 0;
        _xpForNext = 1000;
      });
      getIt<RewardsCubit>().refresh(); // clears it for guests
      getIt<MessagesCubit>().refresh();
    }
  }

  // No endpoint anywhere returns a live coin balance for an authenticated
  // user — `ProfileRepository.fetchStats().coins` reads a JSON key the
  // backend's statsResponse never sends, so this used to always read 0
  // regardless of the real balance (same bug found and fixed on ZProfile's
  // coin pill). `AuthCubit`'s own `coins` field is the real, live value:
  // set at login and bumped on referral redemption / earned coins.
  void _updateCoinsFromAuth() {
    final state = getIt<AuthCubit>().state;
    if (mounted) {
      setState(() => _coins = state is AuthAuthenticated ? state.coins : 0);
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

  Future<void> _fetchLevel() async {
    try {
      final stats = await getIt<ProfileRepository>().fetchStats();
      if (mounted) {
        setState(() {
          _level = stats.level;
          _xpInLevel = stats.xpInLevel;
          _xpForNext = stats.xpForNext;
        });
      }
    } catch (_) {
      // Best-effort — keeps the last known level.
    }
  }

  bool get _isAuthenticated => getIt<AuthCubit>().state is AuthAuthenticated;

  void _startSolo(BuildContext context) {
    context.push(
      '/game',
      extra: const GameRouteArgs(mode: 'classic', opponentType: 'solo'),
    );
  }

  Future<void> _startVsAi(BuildContext context) async {
    final opponentType = await showAiLevelDialog(context);
    if (opponentType == null || !context.mounted) return;
    context.push(
      '/game',
      extra: GameRouteArgs(mode: 'classic', opponentType: opponentType),
    );
  }

  void _startOnline(BuildContext context) {
    if (!_isAuthenticated) {
      context.push('/login?return=/lobby');
    } else {
      context.push('/lobby');
    }
  }

  void _openRoute(BuildContext context, String route) {
    context.push(_isAuthenticated ? route : '/login?return=$route');
  }

  void _resume(BuildContext context) {
    final match = _activeMatch;
    if (match == null) return;
    context.push(
      '/game',
      extra: GameRouteArgs(
        mode: match.mode,
        opponentType: match.opponentType,
        resumeMatchId: match.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;

    return Scaffold(
      backgroundColor: z.paper,
      body: BlocBuilder<MessagesCubit, MessagesState>(
        bloc: getIt<MessagesCubit>(),
        builder:
            (context, messages) => BlocBuilder<RewardsCubit, RewardsState>(
              bloc: getIt<RewardsCubit>(),
              builder:
                  (context, rewards) => HomeView(
                    data: HomeViewData(
                      coins: _coins,
                      streak: _stats?.dailyStreak ?? 0,
                      level: _level,
                      xpInLevel: _xpInLevel,
                      xpForNext: _xpForNext,
                      unclaimedRewards: rewards.unclaimedCount,
                      pendingMessages: messages.count,
                      dailyAttempted: _daily?.hasAttempted ?? false,
                      hasActiveMatch: _checked && _activeMatch != null,
                      // PLACEHOLDER: no endpoint reports players online. The
                      // design's «۳٬۴۰۱» is shown in debug builds only so the
                      // layout can be checked; release shows a real subtitle.
                      onlineCount: kDebugMode ? 3401 : null,
                    ),
                    onPlay: () => _startSolo(context),
                    onAi: () => _startVsAi(context),
                    onOnline: () => _startOnline(context),
                    onDaily: () => context.push('/daily'),
                    onChest: () => _openRoute(context, '/rewards'),
                    onMessages: () => _openRoute(context, '/messages'),
                    // Coin purchase lives in ZProfile's buy sheet.
                    onCoins: () => context.go('/profile'),
                    // The gear is the quick light/dark switch (same ThemeCubit as
                    // ZProfile's حالت شب row).
                    onSettings:
                        () => getIt<ThemeCubit>().toggle(
                          Theme.of(context).brightness,
                        ),
                    onLevel: () => context.go('/profile'),
                    onResume: () => _resume(context),
                  ),
            ),
      ),
    );
  }
}
