import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';

/// ZBoard — the weekly + friends leaderboard.
///
/// Canvas shows 4 tabs (این هفته / امروز / همیشه / دوستان). The backend only
/// ever maintains one leaderboard construct — a single Redis sorted set that
/// resets every Sunday 00:00 UTC (`leaderboard:global:weekly`) — so "امروز"
/// (today) and "همیشه" (all-time) have no real data source anywhere. Per the
/// project's no-fake-mechanics policy (same one applied to ZLobby's wager
/// picker and ZVersus's best-of-5 placeholder), those two tabs are dropped
/// rather than backed by fabricated numbers; only "این هفته" (weekly/global)
/// and "دوستان" (friends) ship, both wired to the real
/// `GET /leaderboard?type=global|friends` endpoint.
class ZBoardScreen extends StatelessWidget {
  const ZBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // GET /leaderboard is behind auth on the backend (CLAUDE.md lists
    // leaderboard viewing itself, not just writes, as requiring
    // registration). The legacy `LeaderboardScreen` never gated this and
    // would loop on a 401 for guests — fixed here with the same guest-gate
    // pattern already used by FriendsScreen/ProfileScreen.
    //
    // Also wrapped in `BlocBuilder<AuthCubit>` + a userId-derived `Key`,
    // same as ZProfileScreen/ZFriendsScreen: this branch is kept alive
    // forever by the shell's IndexedStack, so a one-time `AuthCubit.state`
    // read never picked up sign-out or a different account signing in
    // without an app restart.
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, authState) {
        if (authState is! AuthAuthenticated) {
          return const _GuestGate();
        }
        return BlocProvider(
          key: ValueKey('board-${authState.userId}'),
          create: (_) => LeaderboardCubit(
            repository: getIt<LeaderboardRepository>(),
            currentUserId: authState.userId,
          )..load(),
          child: _BoardView(username: authState.username),
        );
      },
    );
  }
}

class _GuestGate extends StatelessWidget {
  const _GuestGate();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZSpacing.screenGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('جدول', style: ZTypography.screenTitle.copyWith(color: z.ink)),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events_outlined, color: z.ink40, size: 52),
                      const SizedBox(height: ZSpacing.lg),
                      Text(
                        'برای دیدن جدول امتیازات، ثبت‌نام کن',
                        style: ZTypography.body.copyWith(color: z.ink60),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: ZSpacing.xl),
                      AccentButton(
                        label: 'ثبت‌نام رایگان',
                        onPressed: () => context.push('/login?return=/leaderboard'),
                      ),
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

class _BoardView extends StatefulWidget {
  final String username;

  const _BoardView({required this.username});

  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView> {
  int _tab = 0; // 0 = این هفته (global weekly), 1 = دوستان (friends)

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                ZSpacing.screenGutter,
                ZSpacing.lg,
                ZSpacing.screenGutter,
                ZSpacing.md,
              ),
              decoration: BoxDecoration(
                color: z.surface,
                border: Border(bottom: BorderSide(color: z.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('جدول', style: ZTypography.screenTitle.copyWith(color: z.ink)),
                  const SizedBox(height: ZSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _TabPill(
                          label: 'این هفته',
                          selected: _tab == 0,
                          onTap: () => setState(() => _tab = 0),
                        ),
                      ),
                      const SizedBox(width: ZSpacing.sm),
                      Expanded(
                        child: _TabPill(
                          label: 'دوستان',
                          selected: _tab == 1,
                          onTap: () => setState(() => _tab = 1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<LeaderboardCubit, LeaderboardState>(
                builder: (context, state) {
                  if (state is LeaderboardLoading || state is LeaderboardInitial) {
                    return Center(child: CircularProgressIndicator(color: z.indigo));
                  }
                  if (state is LeaderboardError) {
                    return _ErrorState(
                      message: state.message,
                      onRetry: () => context.read<LeaderboardCubit>().load(),
                    );
                  }
                  if (state is LeaderboardLoaded) {
                    final result = _tab == 0 ? state.global : state.friends;
                    return _LeaderboardBody(
                      result: result,
                      username: widget.username,
                      isFriendsTab: _tab == 1,
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

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? z.ink : z.paper,
          borderRadius: BorderRadius.circular(11),
          border: selected ? null : Border.all(color: z.line),
        ),
        child: Text(
          label,
          style: ZTypography.metaLabel.copyWith(
            color: selected ? z.paper : z.ink60,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LeaderboardBody extends StatelessWidget {
  final LeaderboardResult result;
  final String username;
  final bool isFriendsTab;

  const _LeaderboardBody({
    required this.result,
    required this.username,
    required this.isFriendsTab,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final entries = result.entries;

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ZSpacing.xxl),
          child: Text(
            isFriendsTab
                ? 'دوستی نداری یا هنوز کسی این هفته امتیاز نگرفته'
                : 'هنوز کسی این هفته امتیاز نگرفته — اولین نفر باش!',
            style: ZTypography.body.copyWith(color: z.ink60),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final hasPodium = entries.length >= 3;
    final podium = hasPodium ? entries.take(3).toList() : const <LeaderboardEntry>[];
    final restStart = hasPodium ? 3 : 0;
    final rest = entries.length > restStart ? entries.sublist(restStart) : const <LeaderboardEntry>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZSpacing.screenGutter,
        ZSpacing.xl,
        ZSpacing.screenGutter,
        ZSpacing.md,
      ),
      children: [
        if (hasPodium) _Podium(top3: podium),
        if (hasPodium) const SizedBox(height: ZSpacing.xl),
        if (rest.isNotEmpty)
          SolidCard(
            padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg),
            radius: ZRadius.cardMax,
            child: Column(
              children: [
                for (var i = 0; i < rest.length; i++)
                  _RankRow(entry: rest[i], showTopBorder: i > 0),
              ],
            ),
          ),
        const SizedBox(height: ZSpacing.xl),
        _SelfRow(
          rank: result.playerRank,
          score: result.playerScore,
          username: username,
        ),
        const SizedBox(height: ZSpacing.md),
      ],
    );
  }
}

Color _accentColor(ZColors z, ZAccent accent) {
  switch (accent) {
    case ZAccent.indigo:
      return z.indigo;
    case ZAccent.teal:
      return z.teal;
    case ZAccent.amber:
      return z.amber;
    case ZAccent.coral:
      return z.coral;
    case ZAccent.neutral:
      return z.ink;
  }
}

class _Podium extends StatelessWidget {
  /// [top3] is rank-ascending: index 0 = رتبهٔ ۱.
  final List<LeaderboardEntry> top3;

  const _Podium({required this.top3});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 10,
          child: _PedestalCell(entry: top3[1], accent: ZAccent.teal, avatarSize: 46),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 12,
          child: _PedestalCell(entry: top3[0], accent: ZAccent.amber, avatarSize: 56, isFirst: true),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 10,
          child: _PedestalCell(entry: top3[2], accent: ZAccent.coral, avatarSize: 46),
        ),
      ],
    );
  }
}

class _PedestalCell extends StatelessWidget {
  final LeaderboardEntry entry;
  final ZAccent accent;
  final double avatarSize;
  final bool isFirst;

  const _PedestalCell({
    required this.entry,
    required this.accent,
    required this.avatarSize,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final initial = entry.username.isEmpty ? '؟' : entry.username.substring(0, 1).toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFirst) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: -0.1,
                child: LetterTile(
                  letter: toPersianDigits(entry.rank),
                  size: 22,
                  height: 26,
                  accent: accent,
                  radius: 7,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              Transform.rotate(
                angle: 0.1,
                child: LetterTile(
                  letter: initial,
                  size: 22,
                  height: 26,
                  accent: accent,
                  radius: 7,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        LetterTile(letter: initial, size: avatarSize, accent: accent, radius: isFirst ? 16 : 14),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(6, isFirst ? 12 : 10, 6, isFirst ? 20 : 14),
          decoration: BoxDecoration(
            color: z.surface,
            border: Border.all(color: z.line),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isFirst ? 18 : 16),
              topRight: Radius.circular(isFirst ? 18 : 16),
            ),
            boxShadow: ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth),
          ),
          child: Column(
            children: [
              Text(
                entry.username,
                style: ZTypography.cardTitle.copyWith(fontSize: isFirst ? 13 : 12, color: z.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Text(
                formatPersianNumber(entry.score),
                style: ZTypography.cardTitle.copyWith(
                  fontSize: isFirst ? 17 : 15,
                  color: _accentColor(z, accent),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                toPersianDigits(entry.rank),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: isFirst ? 20 : 18,
                  color: z.ink40,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool showTopBorder;

  const _RankRow({required this.entry, required this.showTopBorder});

  static const _accents = [ZAccent.indigo, ZAccent.teal, ZAccent.amber, ZAccent.coral];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final accent = _accents[(entry.rank - 1).clamp(0, 1 << 30) % _accents.length];
    final initial = entry.username.isEmpty ? '؟' : entry.username.substring(0, 1).toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: showTopBorder ? Border(top: BorderSide(color: z.line)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              toPersianDigits(entry.rank),
              style: ZTypography.cardTitle.copyWith(fontSize: 13, color: z.ink40),
            ),
          ),
          const SizedBox(width: ZSpacing.md),
          LetterTile(letter: initial, size: 32, accent: accent, radius: 10, fontSize: 14),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Text(
              entry.username,
              style: ZTypography.cardTitle.copyWith(fontSize: 13.5, color: z.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatPersianNumber(entry.score),
            style: ZTypography.cardTitle.copyWith(fontSize: 14, color: z.ink),
          ),
        ],
      ),
    );
  }
}

class _SelfRow extends StatelessWidget {
  final int rank;
  final int score;
  final String username;

  const _SelfRow({required this.rank, required this.score, required this.username});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final initial = username.isEmpty ? '؟' : username.substring(0, 1).toUpperCase();
    final unranked = rank <= 0;

    final String subtitle;
    if (unranked) {
      subtitle = 'این هفته امتیازی نداری — یک بازی آنلاین یا چالش روزانه بازی کن';
    } else if (rank <= 10) {
      subtitle = 'جزو ده نفر برتری!';
    } else {
      subtitle = '${toPersianDigits(rank - 10)} پله تا ده‌تای اول';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: z.inkSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ZElevation.solidEdge(z.inkSurfaceDeep, depth: ZElevation.tileDepth),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              unranked ? '—' : toPersianDigits(rank),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: z.onInkSurfaceSoft),
            ),
          ),
          const SizedBox(width: ZSpacing.md),
          LetterTile(letter: initial, size: 34, accent: ZAccent.teal, radius: 11, fontSize: 15),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تو — $username',
                  style: ZTypography.cardTitle.copyWith(fontSize: 14, color: z.onInkSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: ZTypography.metaLabel.copyWith(color: z.onInkSurfaceSoft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!unranked)
            Text(
              formatPersianNumber(score),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: z.onInkSurface),
            ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: z.ink40, size: 44),
            const SizedBox(height: ZSpacing.md),
            Text(message, style: ZTypography.body.copyWith(color: z.ink60), textAlign: TextAlign.center),
            const SizedBox(height: ZSpacing.lg),
            NeutralButton(label: 'تلاش دوباره', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
