import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/coin_pill.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';
import 'package:wordchain/features/lobby/cubit/lobby_cubit.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

// Turn-length options shown in ZLobby's picker (REDESIGN_PLAN.md §1
// decision 2: "build exactly as designed, no placeholder gating" — the
// picker is fully interactive local UI, but `POST /match/queue` has no
// field for a custom per-turn duration (CLAUDE.md's turn timers are fixed
// per variant: 15s classic / 8s time attack), so the selection is cosmetic
// and does not change the actual match. Flagged, not silently wired.
const _turnLengthOptions = [10, 15, 20];

// Wager options (REDESIGN_PLAN.md §1 decision 2, same treatment as above —
// there is no wager/coin-stake system in the coin economy or backend).
const _wagerOptions = ['بدون شرط', '۲۰ سکه', '۱۰۰ سکه'];

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LobbyCubit(
        repo: getIt(),
        syncService: getIt(),
        notificationService: getIt(),
      ),
      child: const _LobbyView(),
    );
  }
}

class _LobbyView extends StatefulWidget {
  const _LobbyView();

  @override
  State<_LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends State<_LobbyView> {
  // Real, functional axis — controls the actual /match/queue call. Not part
  // of the canvas (which drops the classic/time-attack choice entirely in
  // favor of the decorative turn-length picker below); kept so multiplayer
  // Time Attack stays reachable rather than silently regressed, the same
  // class of bug flagged and fixed for VS-AI earlier this stage.
  String _mode = 'classic';

  int _turnLength = 15;
  String _wager = _wagerOptions[0];

  int _coins = 0;
  List<FriendModel> _friends = const [];

  @override
  void initState() {
    super.initState();
    _fetchCoins();
    _fetchFriends();
  }

  Future<void> _fetchCoins() async {
    try {
      final stats = await getIt<ProfileRepository>().fetchStats();
      if (mounted) setState(() => _coins = stats.coins);
    } catch (_) {
      // Best-effort — lobby still renders without a live coin count.
    }
  }

  Future<void> _fetchFriends() async {
    try {
      final friends = await getIt<FriendsRepository>().fetchFriends();
      if (mounted) setState(() => _friends = friends.take(2).toList());
    } catch (_) {
      // Best-effort — friends invite list just stays empty.
    }
  }

  Future<void> _challengeFriend(FriendModel friend) async {
    try {
      await getIt<FriendsRepository>().sendChallenge(friend.userId, _mode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('دعوت‌نامه برای ${friend.username} ارسال شد')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ارسال دعوت‌نامه ناموفق بود')),
        );
      }
    }
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('این قابلیت به‌زودی اضافه می‌شود')),
    );
  }

  String get _myUsername {
    final authState = getIt<AuthCubit>().state;
    return authState is AuthAuthenticated ? authState.username : 'تو';
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;

    return BlocConsumer<LobbyCubit, LobbyState>(
      listener: (context, state) {
        if (state is LobbyMatchFound) {
          _navigateToGame(context, state);
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: z.paper,
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(coins: _coins),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                        ZSpacing.screenGutter, 0, ZSpacing.screenGutter, ZSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _VersusCard(
                          state: state,
                          myUsername: _myUsername,
                        ),
                        const SizedBox(height: ZSpacing.lg),
                        switch (state) {
                          LobbySearching s => _SearchingBlock(state: s),
                          LobbyError e => _ErrorBlock(
                              message: e.message,
                              onRetry: () => context.read<LobbyCubit>().startSearch(_mode),
                            ),
                          _ => _IdleBlock(
                              mode: _mode,
                              onModeChanged: (m) => setState(() => _mode = m),
                              turnLength: _turnLength,
                              onTurnLengthChanged: (t) => setState(() => _turnLength = t),
                              wager: _wager,
                              onWagerChanged: (w) => setState(() => _wager = w),
                              onFindMatch: () => context.read<LobbyCubit>().startSearch(_mode),
                            ),
                        },
                        if (state is! LobbySearching) ...[
                          const SizedBox(height: ZSpacing.lg),
                          _InviteRow(onTap: _showComingSoon),
                          if (_friends.isNotEmpty) ...[
                            const SizedBox(height: ZSpacing.lg),
                            _FriendsCard(friends: _friends, onChallenge: _challengeFriend),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToGame(BuildContext context, LobbyMatchFound state) {
    final authState = getIt<AuthCubit>().state;
    final myPlayerId = authState is AuthAuthenticated ? authState.userId : '';

    context.pushReplacement(
      '/game',
      extra: GameRouteArgs(
        mode: state.mode,
        opponentType: 'multiplayer',
        roomId: state.roomId,
        myPlayerId: myPlayerId,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — back, title, coin pill
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final int coins;

  const _TopBar({required this.coins});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter, ZSpacing.md, ZSpacing.screenGutter, ZSpacing.md),
      child: Row(
        children: [
          ZBackButton(onTap: () => context.pop()),
          const SizedBox(width: ZSpacing.md),
          Text('رویارویی آنلاین', style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 19)),
          const Spacer(),
          CoinPill(amount: coins),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Versus card — me vs opponent (placeholder while idle, animated while
// searching, matched name once found)
// ---------------------------------------------------------------------------

class _VersusCard extends StatelessWidget {
  final LobbyState state;
  final String myUsername;

  const _VersusCard({required this.state, required this.myUsername});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final searching = state is LobbySearching;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: ZSpacing.xl),
      decoration: BoxDecoration(
        color: z.inkSurface,
        borderRadius: BorderRadius.circular(ZRadius.cardMax),
        boxShadow: ZElevation.solidEdge(z.inkSurfaceDeep, depth: ZElevation.cardDepth),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _VersusSide(
                  letter: myUsername.isNotEmpty ? myUsername[0] : 'ت',
                  accent: ZAccent.teal,
                  name: myUsername,
                  subtitle: 'حاضر',
                  dim: false,
                ),
              ),
              Text('مقابل',
                  style: ZTypography.metaLabel.copyWith(color: z.onInkSurfaceSoft, fontWeight: FontWeight.w900)),
              Expanded(
                child: _VersusSide(
                  letter: '؟',
                  accent: ZAccent.indigo,
                  name: searching ? 'در جست‌وجو…' : 'آمادهٔ شروع؟',
                  subtitle: 'هم‌سطح تو',
                  dim: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.lg),
          _SearchDots(active: searching),
        ],
      ),
    );
  }
}

class _VersusSide extends StatelessWidget {
  final String letter;
  final ZAccent accent;
  final String name;
  final String subtitle;
  final bool dim;

  const _VersusSide({
    required this.letter,
    required this.accent,
    required this.name,
    required this.subtitle,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      children: [
        Opacity(
          opacity: dim ? 0.65 : 1,
          child: LetterTile(letter: letter, size: 56, accent: accent),
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(name,
            style: ZTypography.cardTitle.copyWith(color: z.onInkSurface, fontSize: 13),
            overflow: TextOverflow.ellipsis),
        Text(subtitle, style: ZTypography.metaLabel.copyWith(color: z.onInkSurfaceSoft, fontSize: 11)),
      ],
    );
  }
}

class _SearchDots extends StatefulWidget {
  final bool active;

  const _SearchDots({required this.active});

  @override
  State<_SearchDots> createState() => _SearchDotsState();
}

class _SearchDotsState extends State<_SearchDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_SearchDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final litIndex = widget.active ? (_ctrl.value * 4).floor().clamp(0, 3) : -1;
        final colors = [z.coral, z.amber, z.teal, z.indigo];
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final lit = widget.active ? i <= litIndex : i < 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lit ? colors[i] : z.onInkSurfaceSoft.withValues(alpha: 0.4),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Idle — pickers + Find Match CTA
// ---------------------------------------------------------------------------

class _IdleBlock extends StatelessWidget {
  final String mode;
  final void Function(String) onModeChanged;
  final int turnLength;
  final void Function(int) onTurnLengthChanged;
  final String wager;
  final void Function(String) onWagerChanged;
  final VoidCallback onFindMatch;

  const _IdleBlock({
    required this.mode,
    required this.onModeChanged,
    required this.turnLength,
    required this.onTurnLengthChanged,
    required this.wager,
    required this.onWagerChanged,
    required this.onFindMatch,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.all(ZSpacing.lg),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border.all(color: z.line),
        borderRadius: BorderRadius.circular(ZRadius.cardMin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('نوع بازی', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
          const SizedBox(height: ZSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _Chip(
                  label: 'کلاسیک',
                  selected: mode == 'classic',
                  onTap: () => onModeChanged('classic'),
                ),
              ),
              const SizedBox(width: ZSpacing.sm),
              Expanded(
                child: _Chip(
                  label: 'زمان‌دار',
                  selected: mode == 'time_attack',
                  onTap: () => onModeChanged('time_attack'),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.lg),
          Text('مدت هر نوبت', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
          const SizedBox(height: ZSpacing.sm),
          Row(
            children: [
              for (final t in _turnLengthOptions) ...[
                if (t != _turnLengthOptions.first) const SizedBox(width: ZSpacing.sm),
                Expanded(
                  child: _Chip(
                    label: '${toPersianDigits(t)} ثانیه',
                    selected: turnLength == t,
                    onTap: () => onTurnLengthChanged(t),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: ZSpacing.lg),
          Text('شرط بازی', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
          const SizedBox(height: ZSpacing.sm),
          Row(
            children: [
              for (final w in _wagerOptions) ...[
                if (w != _wagerOptions.first) const SizedBox(width: ZSpacing.sm),
                Expanded(
                  child: _Chip(
                    label: w,
                    selected: wager == w,
                    accent: ZAccentColor.amber,
                    onTap: () => onWagerChanged(w),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: ZSpacing.xl),
          AccentButton(
            label: 'پیدا کردن حریف',
            accent: ZAccentColor.coral,
            onPressed: onFindMatch,
          ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            'با یک بازیکن آنلاین جفت می‌شوی؛ اگر حریفی پیدا نشود، پس از ۳۰ ثانیه با هوش مصنوعی بازی می‌کنی.',
            textAlign: TextAlign.center,
            style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ZAccentColor accent;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = ZAccentColor.indigo,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (bg, fg) = switch (accent) {
      ZAccentColor.indigo => (z.ink, z.paper),
      ZAccentColor.amber => (z.amber, z.onAmber),
      ZAccentColor.teal => (z.teal, z.onTeal),
      ZAccentColor.coral => (z.coral, z.onCoral),
    };
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? bg : z.paper,
          borderRadius: BorderRadius.circular(ZRadius.tileMin + 2),
          border: selected ? null : Border.all(color: z.line),
        ),
        child: Text(
          label,
          style: ZTypography.metaLabel.copyWith(
            color: selected ? fg : z.ink60,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Searching — elapsed time + cancel
// ---------------------------------------------------------------------------

class _SearchingBlock extends StatelessWidget {
  final LobbySearching state;

  const _SearchingBlock({required this.state});

  String get _elapsed {
    final s = state.elapsedSeconds;
    return toPersianDigits(
        '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      children: [
        Text(_elapsed,
            style: ZTypography.screenTitle.copyWith(
                color: z.ink, fontSize: 26, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: ZSpacing.lg),
        NeutralButton(
          label: 'لغو جست‌وجو',
          onPressed: () => context.read<LobbyCubit>().cancelSearch(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      children: [
        Icon(Icons.wifi_off_rounded, color: z.coral, size: 40),
        const SizedBox(height: ZSpacing.md),
        Text(message, textAlign: TextAlign.center, style: ZTypography.body.copyWith(color: z.ink60)),
        const SizedBox(height: ZSpacing.lg),
        AccentButton(label: 'تلاش دوباره', accent: ZAccentColor.coral, onPressed: onRetry),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Invite by room code — REDESIGN_PLAN.md §1 decision 6 (referral/invite
// codes): rendered as designed, wired to a placeholder — no such join-by-
// code system exists in the backend yet (real friend challenges use
// sendChallenge below instead).
// ---------------------------------------------------------------------------

class _InviteRow extends StatelessWidget {
  final VoidCallback onTap;

  const _InviteRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.md, vertical: ZSpacing.md),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border.all(color: z.line, width: 1.5, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(ZRadius.cardMin),
      ),
      child: Row(
        children: [
          Row(
            children: [
              LetterTile(letter: 'ز', size: 30, accent: ZAccent.indigo, radius: 8),
              const SizedBox(width: 4),
              LetterTile(letter: 'ن', size: 30, accent: ZAccent.teal, radius: 8),
            ],
          ),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('بازی با دوست', style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 13.5)),
                Text('با کد اتاق دعوت کن', style: ZTypography.metaLabel.copyWith(color: z.ink60, fontSize: 11.5)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(color: z.tintIndigo, borderRadius: BorderRadius.circular(999)),
              child: Text('دعوت',
                  style: ZTypography.metaLabel.copyWith(color: z.indigo, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friends — real data (FriendsRepository.fetchFriends), substituting the
// canvas's fabricated per-opponent win/loss "recent opponents" list (no
// match-history-vs-a-friend endpoint exists) with each friend's real weekly
// score, and wiring "دعوت" to the real POST /challenges call instead of a
// fake room-code join.
// ---------------------------------------------------------------------------

class _FriendsCard extends StatelessWidget {
  final List<FriendModel> friends;
  final void Function(FriendModel) onChallenge;

  const _FriendsCard({required this.friends, required this.onChallenge});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      decoration: BoxDecoration(
        color: z.surface,
        border: Border.all(color: z.line),
        borderRadius: BorderRadius.circular(ZRadius.cardMin),
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.md),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZSpacing.md),
            child: Row(
              children: [
                Text('دوستان', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
              ],
            ),
          ),
          for (final friend in friends) ...[
            if (friend != friends.first) Divider(color: z.line, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ZSpacing.sm),
              child: Row(
                children: [
                  LetterTile(
                    letter: friend.username.isNotEmpty ? friend.username[0] : '؟',
                    size: 34,
                    accent: _accentCycle[friends.indexOf(friend) % _accentCycle.length],
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(friend.username, style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 13.5)),
                        Text('${formatPersianNumber(friend.weeklyScore)} امتیاز این هفته',
                            style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => onChallenge(friend),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: z.tintTeal, borderRadius: BorderRadius.circular(999)),
                      child: Text('دعوت',
                          style: ZTypography.metaLabel.copyWith(color: z.teal, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const _accentCycle = [ZAccent.indigo, ZAccent.teal, ZAccent.amber, ZAccent.coral];
