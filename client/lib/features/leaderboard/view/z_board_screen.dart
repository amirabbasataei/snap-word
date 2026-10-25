import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_note.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_parts.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_podium.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_rows.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_self_row.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_tabs.dart';

/// «جدول» — the leaderboard tab, "A · mascot-led" (canvas `ZBoardA`): sky
/// scene, ribbon title, a four-way segmented control, the podium, the ranked
/// list and the player's own row pinned underneath.
///
/// Tabs: «این هفته» (`type=global`, the weekly Redis board), «امروز»
/// (`GET /daily/leaderboard`, today's Daily Challenge), «همیشه» (`type=alltime`)
/// and «دوستان» (`type=friends`). The canvas's «بلندترین زنجیر» sub-line is
/// real only on the daily board (`chain_length`); the other boards carry no
/// such field, so their rows have none. No rank deltas, leagues or player
/// counts exist on the server, so none are drawn.
class ZBoardScreen extends StatelessWidget {
  /// Clock for the countdowns; tests pass a fixed one.
  final DateTime Function()? clock;

  const ZBoardScreen({super.key, this.clock});

  @override
  Widget build(BuildContext context) {
    // GET /leaderboard is behind auth on the backend, so a guest gets a login
    // card instead of a call that would 401. The tab is kept alive by the
    // shell's IndexedStack, so the auth state is watched and the cubit is
    // keyed by user id: sign-out or another account starts from scratch.
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, authState) {
        if (authState is! AuthAuthenticated) {
          return const _BoardFrame(child: _GuestBody());
        }
        return BlocProvider(
          key: ValueKey('board-${authState.userId}'),
          create:
              (_) => LeaderboardCubit(
                repository: getIt<LeaderboardRepository>(),
                currentUserId: authState.userId,
              )..load(),
          child: TabRefreshListener(
            index: MainTab.board,
            onRefresh: (ctx) => ctx.read<LeaderboardCubit>().load(silent: true),
            child: _BoardView(username: authState.username, clock: clock),
          ),
        );
      },
    );
  }
}

/// Scene, ribbon title and a body slot — what every state shares.
class _BoardFrame extends StatelessWidget {
  final Widget child;

  const _BoardFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zs.sky3,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeSceneBackground()),
          SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(14, 10, 14, 0),
                  child: Center(
                    child: ZRibbonTitle(
                      'جدول',
                      accent: ZDialogAccent.indigo,
                      expand: false,
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width card for the states that have no list (loading, failed,
/// guest, an empty board).
class _StateCard extends StatelessWidget {
  final Widget child;

  const _StateCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ChunkyBox(
      fill: context.z.surface,
      depth: ZGame.depthMd,
      radius: 22,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: child,
    );
  }
}

class _GuestBody extends StatelessWidget {
  const _GuestBody();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: _StateCard(
        child: ZEmptyState(
          title: 'جدول را ببین',
          body: 'برای دیدن جدول امتیازات، ثبت‌نام کن',
          actionLabel: 'ثبت‌نام رایگان',
          onAction: () => context.push('/login?return=/leaderboard'),
        ),
      ),
    );
  }
}

class _BoardView extends StatelessWidget {
  final String username;
  final DateTime Function()? clock;

  const _BoardView({required this.username, required this.clock});

  @override
  Widget build(BuildContext context) {
    return _BoardFrame(
      child: BlocBuilder<LeaderboardCubit, LeaderboardState>(
        builder: (context, state) {
          final cubit = context.read<LeaderboardCubit>();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: BoardTabs(selected: state.tab, onSelect: cubit.select),
              ),
              Expanded(
                child: _TabBody(
                  state: state,
                  username: username,
                  now: (clock ?? DateTime.now)(),
                  onRetry: cubit.load,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  final LeaderboardState state;
  final String username;
  final DateTime now;
  final VoidCallback onRetry;

  const _TabBody({
    required this.state,
    required this.username,
    required this.now,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final result = state.current;
    if (result == null) {
      final error = state.errors[state.tab];
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: _StateCard(
          child:
              error != null
                  ? ZLoadState.error(message: error, onRetry: onRetry)
                  : const ZLoadState.loading(),
        ),
      );
    }

    final tab = state.tab;
    final mine = state.currentUserId;
    final entries = result.entries;
    // The friends board always holds the player, so «no friends» is a board of
    // one.
    final empty =
        entries.isEmpty ||
        (tab == BoardTab.friends &&
            entries.every((e) => e.userId == state.currentUserId));
    if (empty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: _StateCard(child: _EmptyBoard(tab: tab)),
      );
    }

    final hasPodium = entries.length >= 3;
    final rest = hasPodium ? entries.sublist(3) : entries;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              BoardNote(tab: tab, now: now, dayNumber: result.dayNumber),
              if (hasPodium)
                BoardPodium(
                  top3: entries.take(3).toList(),
                  currentUserId: mine,
                ),
              if (hasPodium && rest.isEmpty)
                // Nothing under the pedestals: close them with the card's rim.
                const SizedBox(height: 4)
              else if (rest.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: hasPodium ? 0 : 12),
                  child: BoardRowsCard(
                    entries: rest,
                    currentUserId: mine,
                    underPodium: hasPodium,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: BoardSelfRow(
            username: username,
            avatarId: result.playerAvatarId ?? state.selfAvatarId,
            rank: result.playerRank,
            score: result.playerScore,
            subtitle: selfSubtitle(tab, result.playerRank, result.playerScore),
          ),
        ),
      ],
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  final BoardTab tab;

  const _EmptyBoard({required this.tab});

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      BoardTab.weekly => const ZEmptyState(
        title: 'هنوز کسی امتیاز نگرفته',
        body: 'این هفته اولین نفر باش — یک بازی آنلاین بازی کن.',
      ),
      BoardTab.daily => ZEmptyState(
        mood: ZMascotMood.thinking,
        title: 'امروز هنوز کسی بازی نکرده',
        body: 'اولین نفر چالش روزانه باش!',
        actionLabel: 'چالش روزانه',
        onAction: () => context.push('/daily'),
      ),
      BoardTab.allTime => const ZEmptyState(
        title: 'هنوز کسی امتیازی ندارد',
        body: 'اولین نفر باش — یک بازی آنلاین بازی کن.',
      ),
      BoardTab.friends => ZEmptyState(
        title: 'هنوز دوستی نداری',
        body: 'دوست اضافه کن تا امتیاز این هفته‌تان را کنار هم ببینی.',
        actionLabel: 'افزودن دوست',
        onAction: () => context.go('/friends'),
      ),
    };
  }
}
