import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/widgets/insufficient_coins_dialog.dart';
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
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/lobby/cubit/lobby_cubit.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => LobbyCubit(
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
  static const _mode = 'classic';

  List<FriendModel> _friends = const [];

  @override
  void initState() {
    super.initState();
    _fetchFriends();
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
      final repo = getIt<FriendsRepository>();
      final mode = _mode;
      final challengeId = await repo.sendChallenge(friend.userId, mode);
      if (mounted) {
        ZToast.show(
          context,
          'دعوت‌نامه برای ${friend.username} ارسال شد',
          kind: ZToastKind.success,
        );
      }
      if (challengeId == null) return;
      // Wait for the friend to accept, then join the same room.
      final roomId = await repo.waitForChallengeRoom(
        challengeId,
        isCancelled: () => !mounted,
      );
      if (roomId != null && mounted) {
        context.push(
          '/game',
          extra: GameRouteArgs(
            mode: mode,
            opponentType: 'multiplayer',
            roomId: roomId,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e is FriendsException && e.code == 'insufficient_coins') {
          showInsufficientCoinsDialog(context);
        } else {
          ZToast.show(
            context,
            'ارسال دعوت‌نامه ناموفق بود',
            kind: ZToastKind.error,
          );
        }
      }
    }
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
        if (state is LobbyError && state.insufficientCoins) {
          context.read<LobbyCubit>().reset();
          showInsufficientCoinsDialog(context);
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: z.paper,
          body: SafeArea(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      ZSpacing.screenGutter,
                      0,
                      ZSpacing.screenGutter,
                      ZSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _VersusCard(state: state, myUsername: _myUsername),
                        const SizedBox(height: ZSpacing.lg),
                        switch (state) {
                          LobbySearching s => _SearchingBlock(state: s),
                          LobbyError e => _ErrorBlock(
                            message: e.message,
                            onRetry:
                                () => context.read<LobbyCubit>().startSearch(
                                  _mode,
                                ),
                          ),
                          _ => _IdleBlock(
                            onFindMatch:
                                () => context.read<LobbyCubit>().startSearch(
                                  _mode,
                                ),
                          ),
                        },
                        if (state is! LobbySearching) ...[
                          const SizedBox(height: ZSpacing.lg),
                          if (_friends.isNotEmpty)
                            _FriendsCard(
                              friends: _friends,
                              onChallenge: _challengeFriend,
                            ),
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
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZSpacing.screenGutter,
        ZSpacing.md,
        ZSpacing.screenGutter,
        ZSpacing.md,
      ),
      child: Row(
        children: [
          ZBackButton(onTap: () => context.pop()),
          const SizedBox(width: ZSpacing.md),
          Text(
            'رویارویی آنلاین',
            style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 19),
          ),
          const Spacer(),
          // AuthCubit holds the live balance; fetchStats() never returns coins.
          BlocBuilder<AuthCubit, AuthState>(
            bloc: getIt<AuthCubit>(),
            builder:
                (context, auth) => CoinPill(
                  amount: auth is AuthAuthenticated ? auth.coins : 0,
                ),
          ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: ZSpacing.lg,
        vertical: ZSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: z.inkSurface,
        borderRadius: BorderRadius.circular(ZRadius.cardMax),
        boxShadow: ZElevation.solidEdge(
          z.inkSurfaceDeep,
          depth: ZElevation.cardDepth,
        ),
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
              Text(
                'مقابل',
                style: ZTypography.metaLabel.copyWith(
                  color: z.onInkSurfaceSoft,
                  fontWeight: FontWeight.w900,
                ),
              ),
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
        Text(
          name,
          style: ZTypography.cardTitle.copyWith(
            color: z.onInkSurface,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          subtitle,
          style: ZTypography.metaLabel.copyWith(
            color: z.onInkSurfaceSoft,
            fontSize: 11,
          ),
        ),
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

class _SearchDotsState extends State<_SearchDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
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
        final litIndex =
            widget.active ? (_ctrl.value * 4).floor().clamp(0, 3) : -1;
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
                  color:
                      lit
                          ? colors[i]
                          : z.onInkSurfaceSoft.withValues(alpha: 0.4),
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
  final VoidCallback onFindMatch;

  const _IdleBlock({required this.onFindMatch});

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
          const _EntryFeeRow(),
          const SizedBox(height: ZSpacing.lg),
          AccentButton(
            label: 'پیدا کردن حریف',
            accent: ZAccentColor.coral,
            onPressed: onFindMatch,
          ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            'با یک بازیکن آنلاین جفت می‌شوی؛ اگر حریفی پیدا نشود، پس از ۳۰ ثانیه با هوش مصنوعی بازی می‌کنی و ورودی نمی‌دهی.',
            textAlign: TextAlign.center,
            style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11),
          ),
        ],
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
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      children: [
        Text(
          _elapsed,
          style: ZTypography.screenTitle.copyWith(
            color: z.ink,
            fontSize: 26,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
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
        Text(
          message,
          textAlign: TextAlign.center,
          style: ZTypography.body.copyWith(color: z.ink60),
        ),
        const SizedBox(height: ZSpacing.lg),
        AccentButton(
          label: 'تلاش دوباره',
          accent: ZAccentColor.coral,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Entry fee — fixed stake for human-vs-human matches (config.EntryFeeCoins on
// the backend); the winner takes the whole pot.
// ---------------------------------------------------------------------------

class _EntryFeeRow extends StatelessWidget {
  const _EntryFeeRow();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZSpacing.md,
        vertical: ZSpacing.md,
      ),
      decoration: BoxDecoration(
        color: z.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(ZRadius.tileMin + 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'ورودی بازی',
              style: ZTypography.metaLabel.copyWith(
                color: z.ink60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${toPersianDigits(GameConstants.entryFeeCoins)} سکه',
            style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 13.5),
          ),
          const SizedBox(width: ZSpacing.md),
          Text(
            'جایزهٔ برنده',
            style: ZTypography.metaLabel.copyWith(
              color: z.ink60,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Text(
            '${toPersianDigits(GameConstants.entryFeePot)} سکه',
            style: ZTypography.cardTitle.copyWith(
              color: z.teal,
              fontSize: 13.5,
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
// score, and wiring "دعوت" to the real POST /challenges call.
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
                Text(
                  'دوستان',
                  style: ZTypography.metaLabel.copyWith(color: z.ink40),
                ),
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
                    letter:
                        friend.username.isNotEmpty ? friend.username[0] : '؟',
                    size: 34,
                    accent:
                        _accentCycle[friends.indexOf(friend) %
                            _accentCycle.length],
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend.username,
                          style: ZTypography.cardTitle.copyWith(
                            color: z.ink,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          '${formatPersianNumber(friend.weeklyScore)} امتیاز این هفته',
                          style: ZTypography.metaLabel.copyWith(
                            color: z.ink40,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => onChallenge(friend),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: z.tintTeal,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'دعوت',
                        style: ZTypography.metaLabel.copyWith(
                          color: z.teal,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
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

const _accentCycle = [
  ZAccent.indigo,
  ZAccent.teal,
  ZAccent.amber,
  ZAccent.coral,
];
