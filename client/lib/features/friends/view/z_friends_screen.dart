import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/view/widgets/referral_bottom_sheet.dart';
import 'package:wordchain/features/friends/cubit/friends_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/friends/view/friend_challenge_sheet.dart';
import 'package:wordchain/features/game/view/game_screen.dart';

/// ZFriends.
///
/// The canvas splits friends into "آنلاین"/"آفلاین" (online/offline)
/// sections with a per-friend "در بازی · دست ۳" / "منتظر نوبت تو" status.
/// No presence system exists anywhere in the backend (no WS presence
/// broadcast, no online/last-seen column, no in-match status endpoint) —
/// `FriendsRepository`/`FriendModel` only ever carries `userId`/`username`/
/// `weeklyScore`. Rather than fabricate online status, every friend is
/// rendered in one real "دوستان" list, exactly matching the data the legacy
/// `FriendsScreen` already showed. Flagged in the Stage 5 report.
class ZFriendsScreen extends StatelessWidget {
  const ZFriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Same fix as ZProfileScreen: this branch is kept alive forever by the
    // shell's IndexedStack, so a one-time `isGuest` read never picked up
    // sign-out (or a different account signing in) without an app restart.
    // `BlocBuilder<AuthCubit>` + a userId-derived `Key` forces a fresh
    // `FriendsCubit`/guest-gate on every real auth transition.
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, authState) {
        if (authState is! AuthAuthenticated) {
          return const _GuestGate();
        }
        return BlocProvider(
          key: ValueKey('friends-${authState.userId}'),
          create: (_) => FriendsCubit(repository: getIt<FriendsRepository>())..load(),
          child: const _FriendsView(),
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
              Text('دوستان', style: ZTypography.screenTitle.copyWith(color: z.ink)),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_outlined, color: z.ink40, size: 52),
                      const SizedBox(height: ZSpacing.lg),
                      Text(
                        'ثبت‌نام کن تا دوست اضافه کنی، چالش بفرستی و رقابت کنی!',
                        style: ZTypography.body.copyWith(color: z.ink60),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: ZSpacing.xl),
                      AccentButton(
                        label: 'ثبت‌نام رایگان',
                        onPressed: () => context.push('/login?return=/friends')
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

class _FriendsView extends StatefulWidget {
  const _FriendsView();

  @override
  State<_FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<_FriendsView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return BlocListener<FriendsCubit, FriendsState>(
      listener: (context, state) {
        if (state is ChallengAccepted) {
          context.push(
            '/game',
            extra: GameRouteArgs(
              mode: state.mode,
              opponentType: 'multiplayer',
              roomId: state.roomId,
            ),
          );
        }
        if (state is FriendActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: z.teal),
          );
        }
        if (state is FriendsLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!), backgroundColor: z.coral),
          );
        }
      },
      child: Scaffold(
        backgroundColor: z.paper,
        body: SafeArea(
          child: BlocBuilder<FriendsCubit, FriendsState>(
            builder: (context, state) {
              if (state is FriendsLoading || state is FriendsInitial) {
                return Center(child: CircularProgressIndicator(color: z.indigo));
              }
              if (state is FriendsError) {
                return _ErrorState(
                  message: state.message,
                  onRetry: () => context.read<FriendsCubit>().load(),
                );
              }
              if (state is FriendsLoaded) {
                return _LoadedBody(
                  state: state,
                  searchController: _searchController,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}

class _LoadedBody extends StatefulWidget {
  final FriendsLoaded state;
  final TextEditingController searchController;

  const _LoadedBody({required this.state, required this.searchController});

  @override
  State<_LoadedBody> createState() => _LoadedBodyState();
}

class _LoadedBodyState extends State<_LoadedBody> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  void _showAddFriendDialog(BuildContext context) {
    final z = context.z;
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: z.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZRadius.cardMax)),
        title: Text('افزودن دوست', style: ZTypography.cardTitle.copyWith(color: z.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: ZTypography.body.copyWith(color: z.ink),
          decoration: InputDecoration(
            hintText: 'نام کاربری را وارد کن',
            hintStyle: ZTypography.body.copyWith(color: z.ink40),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('انصراف', style: TextStyle(color: z.ink60)),
          ),
          TextButton(
            onPressed: () {
              final username = controller.text.trim();
              if (username.isNotEmpty) {
                Navigator.pop(ctx);
                context.read<FriendsCubit>().sendFriendRequest(username);
              }
            },
            child: Text('ارسال درخواست', style: TextStyle(color: z.indigo, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final state = widget.state;
    final query = widget.searchController.text.trim().toLowerCase();
    final pendingTotal = state.pendingRequests.length + state.pendingChallenges.length;
    final filteredFriends = query.isEmpty
        ? state.friends
        : state.friends.where((f) => f.username.toLowerCase().contains(query)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZSpacing.screenGutter,
        ZSpacing.lg,
        ZSpacing.screenGutter,
        ZSpacing.xl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('دوستان', style: ZTypography.screenTitle.copyWith(color: z.ink)),
            ),
            GestureDetector(
              onTap: () => _showAddFriendDialog(context),
              child: const _AddButton(),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.lg),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg),
          decoration: BoxDecoration(
            color: z.surface,
            border: Border.all(color: z.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: z.ink40, size: 18),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: TextField(
                  controller: widget.searchController,
                  style: ZTypography.body.copyWith(color: z.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'جست‌وجوی نام یا شناسه',
                    hintStyle: ZTypography.body.copyWith(color: z.ink40),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.lg),
        _ReferralBanner(onTap: () => ReferralBottomSheet.show(context)),
        const SizedBox(height: ZSpacing.xl),
        if (pendingTotal > 0) ...[
          Row(
            children: [
              Text('درخواست‌ها', style: ZTypography.cardTitle.copyWith(fontSize: 12.5, color: z.ink)),
              const SizedBox(width: ZSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: z.coral, borderRadius: BorderRadius.circular(ZRadius.chip)),
                child: Text(
                  toPersianDigits(pendingTotal),
                  style: ZTypography.metaLabel.copyWith(color: z.onCoral, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.sm),
          SolidCard(
            padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg),
            radius: ZRadius.cardMax,
            child: Column(
              children: [
                for (var i = 0; i < state.pendingRequests.length; i++)
                  _PendingRequestRow(request: state.pendingRequests[i], showTopBorder: i > 0),
                for (var i = 0; i < state.pendingChallenges.length; i++)
                  _PendingChallengeRow(
                    challenge: state.pendingChallenges[i],
                    showTopBorder: i > 0 || state.pendingRequests.isNotEmpty,
                  ),
              ],
            ),
          ),
          const SizedBox(height: ZSpacing.xl),
        ],
        Row(
          children: [
            Text('دوستان', style: ZTypography.cardTitle.copyWith(fontSize: 12.5, color: z.ink)),
            const Spacer(),
            Text(
              '${toPersianDigits(filteredFriends.length)} نفر',
              style: ZTypography.metaLabel.copyWith(color: z.ink40),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        if (filteredFriends.isEmpty)
          SolidCard(
            radius: ZRadius.cardMax,
            child: Center(
              child: Text(
                state.friends.isEmpty ? 'هنوز دوستی نداری — یکی اضافه کن!' : 'نتیجه‌ای پیدا نشد',
                style: ZTypography.body.copyWith(color: z.ink40),
              ),
            ),
          )
        else
          SolidCard(
            padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg),
            radius: ZRadius.cardMax,
            child: Column(
              children: [
                for (var i = 0; i < filteredFriends.length; i++)
                  _FriendRow(friend: filteredFriends[i], showTopBorder: i > 0),
              ],
            ),
          ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: z.tintIndigo, borderRadius: BorderRadius.circular(ZRadius.chip)),
      child: Text(
        'افزودن',
        style: ZTypography.metaLabel.copyWith(color: z.indigo, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Referral banner — repurposed to the real redeem flow.
//
// The canvas shows "با کد دعوت، ۵۰ سکه بگیر" with the CALLER's OWN code
// ("کد تو: ZNJR-۴۸۲") to share outward. No endpoint anywhere returns the
// logged-in user's own referral_code (verifyOTPResponse/statsResponse/etc.
// all omit it — it's only ever an INPUT field on verify-otp/redeem). That
// half of the card can't be built without fabricating a code. The tap
// target is wired to the real, already-shipped redeem flow
// (ReferralBottomSheet, same one used from Profile → Settings) instead,
// since entering a friend's code is the one half of this feature that is
// real. Flagged in the Stage 5 report.
// ---------------------------------------------------------------------------

class _ReferralBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _ReferralBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: 15),
        decoration: BoxDecoration(
          color: z.indigo,
          borderRadius: BorderRadius.circular(ZRadius.cardMax),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'کد دعوت داری؟ ۵۰ سکه بگیر',
                    style: ZTypography.cardTitle.copyWith(color: z.onIndigo, fontSize: 13.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'یک‌بار وارد کن',
                    style: ZTypography.metaLabel.copyWith(color: z.onIndigoSoft),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(color: z.surface, borderRadius: BorderRadius.circular(ZRadius.chip)),
              child: Text(
                'وارد کردن کد',
                style: ZTypography.metaLabel.copyWith(color: z.indigo, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending request / challenge rows
// ---------------------------------------------------------------------------

class _PendingRequestRow extends StatelessWidget {
  final PendingRequest request;
  final bool showTopBorder;

  const _PendingRequestRow({required this.request, required this.showTopBorder});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: showTopBorder ? Border(top: BorderSide(color: z.line)) : null),
      child: Row(
        children: [
          _NameAvatar(name: request.username, accent: ZAccent.amber),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.username, style: ZTypography.cardTitle.copyWith(fontSize: 13.5, color: z.ink)),
                Text('می‌خواهد دوست تو شود', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
              ],
            ),
          ),
          _PillAction(
            label: 'تأیید',
            bg: z.teal,
            fg: z.onTeal,
            onTap: () => context.read<FriendsCubit>().respondToRequest(request.requesterId, true),
          ),
          const SizedBox(width: 6),
          _PillAction(
            label: 'رد',
            bg: z.paper,
            fg: z.ink40,
            onTap: () => context.read<FriendsCubit>().respondToRequest(request.requesterId, false),
          ),
        ],
      ),
    );
  }
}

class _PendingChallengeRow extends StatelessWidget {
  final PendingChallenge challenge;
  final bool showTopBorder;

  const _PendingChallengeRow({required this.challenge, required this.showTopBorder});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final modeName = challenge.mode == 'classic' ? 'کلاسیک' : 'زمان‌دار';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: showTopBorder ? Border(top: BorderSide(color: z.line)) : null),
      child: Row(
        children: [
          _NameAvatar(name: challenge.challengerUsername, accent: ZAccent.coral),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(challenge.challengerUsername, style: ZTypography.cardTitle.copyWith(fontSize: 13.5, color: z.ink)),
                Text('چالش فرستاد · $modeName', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
              ],
            ),
          ),
          _PillAction(
            label: 'تأیید',
            bg: z.teal,
            fg: z.onTeal,
            onTap: () => context.read<FriendsCubit>().respondToChallenge(challenge.id, true, challenge.mode),
          ),
          const SizedBox(width: 6),
          _PillAction(
            label: 'رد',
            bg: z.paper,
            fg: z.ink40,
            onTap: () => context.read<FriendsCubit>().respondToChallenge(challenge.id, false, challenge.mode),
          ),
        ],
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _PillAction({required this.label, required this.bg, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ZRadius.chip)),
        child: Text(label, style: ZTypography.metaLabel.copyWith(color: fg, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friend row
// ---------------------------------------------------------------------------

class _FriendRow extends StatelessWidget {
  final FriendModel friend;
  final bool showTopBorder;

  const _FriendRow({required this.friend, required this.showTopBorder});

  void _showChallengeSheet(BuildContext context) {
    final cubit = context.read<FriendsCubit>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FriendChallengeSheet(
        friendUsername: friend.username,
        onSend: (mode) => cubit.sendChallenge(friend.userId, mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: showTopBorder ? Border(top: BorderSide(color: z.line)) : null),
      child: Row(
        children: [
          _NameAvatar(name: friend.username, accent: ZAccent.indigo),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friend.username, style: ZTypography.cardTitle.copyWith(fontSize: 13.5, color: z.ink)),
                Text(
                  friend.weeklyScore > 0
                      ? '${toPersianDigits(friend.weeklyScore)} امتیاز این هفته'
                      : 'بدون امتیاز این هفته',
                  style: ZTypography.metaLabel.copyWith(color: z.ink40),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showChallengeSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(color: z.tintCoral, borderRadius: BorderRadius.circular(ZRadius.chip)),
              child: Text(
                'رویارویی',
                style: ZTypography.metaLabel.copyWith(color: z.coral, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameAvatar extends StatelessWidget {
  final String name;
  final ZAccent accent;

  const _NameAvatar({required this.name, required this.accent});

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '؟' : name.substring(0, 1).toUpperCase();
    return LetterTile(letter: initial, size: 34, accent: accent, radius: 11, fontSize: 15);
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

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
