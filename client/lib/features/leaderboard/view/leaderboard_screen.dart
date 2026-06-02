import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = getIt<AuthCubit>().state;
    final userId =
        authState is AuthAuthenticated ? authState.userId : '';

    return BlocProvider(
      create: (_) => LeaderboardCubit(
        repository: getIt<LeaderboardRepository>(),
        currentUserId: userId,
      )..load(),
      child: const _LeaderboardView(),
    );
  }
}

class _LeaderboardView extends StatefulWidget {
  const _LeaderboardView();

  @override
  State<_LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<_LeaderboardView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Text(
                'Leaderboard',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SegmentedTab(controller: _tabController),
            ),
            const SizedBox(height: 12),
            const _WeeklyResetRow(),
            const SizedBox(height: 12),
            Expanded(
              child: BlocBuilder<LeaderboardCubit, LeaderboardState>(
                builder: (context, state) {
                  if (state is LeaderboardLoading ||
                      state is LeaderboardInitial) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is LeaderboardError) {
                    return _ErrorView(
                      message: state.message,
                      onRetry: () =>
                          context.read<LeaderboardCubit>().load(),
                    );
                  }
                  if (state is LeaderboardLoaded) {
                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _LeaderboardList(
                          result: state.global,
                          currentUserId: state.currentUserId,
                        ),
                        _LeaderboardList(
                          result: state.friends,
                          currentUserId: state.currentUserId,
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented tab control
// ---------------------------------------------------------------------------

class _SegmentedTab extends StatefulWidget {
  final TabController controller;

  const _SegmentedTab({required this.controller});

  @override
  State<_SegmentedTab> createState() => _SegmentedTabState();
}

class _SegmentedTabState extends State<_SegmentedTab> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      if (!widget.controller.indexIsChanging) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'Global',
            isSelected: widget.controller.index == 0,
            onTap: () => widget.controller.animateTo(0),
          ),
          _Tab(
            label: 'Friends',
            isSelected: widget.controller.index == 1,
            onTap: () => widget.controller.animateTo(1),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 14,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly reset countdown row
// ---------------------------------------------------------------------------

class _WeeklyResetRow extends StatelessWidget {
  const _WeeklyResetRow();

  String _resetIn() {
    final now = DateTime.now().toUtc();
    // Next Sunday 00:00 UTC (weekday 7 = Sunday)
    var daysUntilSunday = 7 - now.weekday;
    if (daysUntilSunday == 0) daysUntilSunday = 7;
    final nextSunday = DateTime.utc(
      now.year,
      now.month,
      now.day + daysUntilSunday,
    );
    final diff = nextSunday.difference(now);
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Text(
            'Weekly reset in',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const Spacer(),
          Text(
            _resetIn(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full leaderboard list: podium + ranked rows + sticky "you" bar
// ---------------------------------------------------------------------------

class _LeaderboardList extends StatelessWidget {
  final LeaderboardResult result;
  final String currentUserId;

  const _LeaderboardList({
    required this.result,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final entries = result.entries;

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No scores yet this week',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final top3 = entries.take(3).toList();
    final rest = entries.skip(3).toList();

    // Current user entry — may be null if not yet on the board
    final currentEntry = entries
        .where((e) => e.userId == currentUserId)
        .cast<LeaderboardEntry?>()
        .firstOrNull;

    final showYouBar = currentUserId.isNotEmpty &&
        (currentEntry != null || result.playerRank > 0);

    final playerRank =
        currentEntry?.rank ?? result.playerRank;
    final playerScore =
        currentEntry?.score ?? result.playerScore;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.only(bottom: showYouBar ? 64 : 0),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PodiumRow(
                top3: top3,
                currentUserId: currentUserId,
              ),
            ),
            const SizedBox(height: 4),
            ...rest.map(
              (e) => _RankRow(
                entry: e,
                isCurrentUser: e.userId == currentUserId,
              ),
            ),
          ],
        ),
        if (showYouBar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _YourRankBar(
              rank: playerRank,
              score: playerScore,
              username: currentEntry?.username ?? 'You',
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Podium: top 3 cards
// ---------------------------------------------------------------------------

class _PodiumRow extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  final String currentUserId;

  const _PodiumRow({required this.top3, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: top3.asMap().entries.map((entry) {
        final idx = entry.key;
        final e = entry.value;
        final isFirst = idx == 0;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: idx > 0 ? 8 : 0,
            ),
            child: _PodiumCard(
              entry: e,
              medal: _medal(e.rank),
              highlight: isFirst,
              isCurrentUser: e.userId == currentUserId,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _medal(int rank) {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '';
    }
  }
}

class _PodiumCard extends StatelessWidget {
  final LeaderboardEntry entry;
  final String medal;
  final bool highlight;
  final bool isCurrentUser;

  const _PodiumCard({
    required this.entry,
    required this.medal,
    required this.highlight,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.secondary.withValues(alpha: 0.12)
            : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: highlight
            ? Border.all(
                color: AppColors.secondary.withValues(alpha: 0.6),
                width: 1.5,
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(medal, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          _Avatar(
            initials: _initials(entry.username),
            highlight: highlight,
            size: highlight ? 44 : 36,
          ),
          const SizedBox(height: 6),
          Text(
            entry.username,
            style: TextStyle(
              color: isCurrentUser
                  ? AppColors.primary
                  : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            _formatScore(entry.score),
            style: TextStyle(
              color: highlight ? AppColors.secondary : AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String username) {
    if (username.isEmpty) return '?';
    return username.substring(0, username.length.clamp(0, 2)).toUpperCase();
  }

  String _formatScore(int score) {
    if (score >= 1000) {
      return '${(score / 1000).toStringAsFixed(score % 1000 == 0 ? 0 : 1)}k';
    }
    return '$score';
  }
}

// ---------------------------------------------------------------------------
// Rank rows (4th place onwards)
// ---------------------------------------------------------------------------

class _RankRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isCurrentUser;

  const _RankRow({required this.entry, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: isCurrentUser
          ? BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _Avatar(
            initials: _initials(entry.username),
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isCurrentUser ? 'You' : entry.username,
              style: TextStyle(
                color: isCurrentUser
                    ? AppColors.primary
                    : AppColors.textPrimary,
                fontSize: 14,
                fontWeight:
                    isCurrentUser ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            _formatScore(entry.score),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String username) {
    if (username.isEmpty) return '?';
    return username.substring(0, username.length.clamp(0, 2)).toUpperCase();
  }

  String _formatScore(int score) {
    if (score >= 1000) {
      return '${(score / 1000).toStringAsFixed(score % 1000 == 0 ? 0 : 1)}k';
    }
    return '$score';
  }
}

// ---------------------------------------------------------------------------
// Sticky "Your rank" bar at the bottom
// ---------------------------------------------------------------------------

class _YourRankBar extends StatelessWidget {
  final int rank;
  final int score;
  final String username;

  const _YourRankBar({
    required this.rank,
    required this.score,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              rank > 0 ? '$rank' : '—',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _Avatar(
            initials: username.substring(0, username.length.clamp(0, 2)).toUpperCase(),
            highlight: true,
            size: 34,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'You',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            score > 0 ? _formatScore(score) : '—',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatScore(int s) {
    if (s >= 1000) {
      return '${(s / 1000).toStringAsFixed(s % 1000 == 0 ? 0 : 1)}k';
    }
    return '$s';
  }
}

// ---------------------------------------------------------------------------
// Shared avatar widget
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  final String initials;
  final bool highlight;
  final double size;

  const _Avatar({
    required this.initials,
    this.highlight = false,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.2)
            : AppColors.inputFill,
        border: highlight
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: highlight ? AppColors.primary : AppColors.textSecondary,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w700,
          ),
        ),
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
    return Center(
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
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
