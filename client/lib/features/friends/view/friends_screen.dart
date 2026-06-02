import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/cubit/friends_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/friends/view/friend_challenge_sheet.dart';
import 'package:wordchain/features/game/view/game_screen.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isGuest = getIt<AuthCubit>().isGuest;

    if (isGuest) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Friends',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const Expanded(child: _GuestPlaceholder()),
              ],
            ),
          ),
        ),
      );
    }

    return BlocProvider(
      create: (_) => FriendsCubit(
        repository: getIt<FriendsRepository>(),
      )..load(),
      child: const _FriendsView(),
    );
  }
}

class _GuestPlaceholder extends StatelessWidget {
  const _GuestPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline,
                color: AppColors.textSecondary, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Register to add friends,\nsend challenges, and compete!',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.push('/register'),
              child: const Text('Register Free'),
            ),
          ],
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
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        if (state is FriendsLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionError!),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(
                  'Friends',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search by username...',
                    prefixIcon: Icon(Icons.search,
                        color: AppColors.textSecondary, size: 20),
                  ),
                  style: const TextStyle(color: AppColors.textPrimary),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: BlocBuilder<FriendsCubit, FriendsState>(
                  builder: (context, state) {
                    if (state is FriendsLoading ||
                        state is FriendsInitial) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (state is FriendsError) {
                      return _ErrorView(
                        message: state.message,
                        onRetry: () =>
                            context.read<FriendsCubit>().load(),
                      );
                    }
                    if (state is FriendsLoaded) {
                      return _LoadedBody(
                        state: state,
                        searchQuery: _searchController.text.toLowerCase(),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded body: pending section + friends list + add friend button
// ---------------------------------------------------------------------------

class _LoadedBody extends StatelessWidget {
  final FriendsLoaded state;
  final String searchQuery;

  const _LoadedBody({required this.state, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final pendingTotal =
        state.pendingRequests.length + state.pendingChallenges.length;

    final filteredFriends = searchQuery.isEmpty
        ? state.friends
        : state.friends
            .where((f) =>
                f.username.toLowerCase().contains(searchQuery))
            .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Pending section
        if (pendingTotal > 0) ...[
          _SectionHeader(
            title: 'PENDING ($pendingTotal)',
            paddingTop: 0,
          ),
          ...state.pendingRequests.map(
            (req) => _PendingRequestCard(request: req),
          ),
          ...state.pendingChallenges.map(
            (ch) => _PendingChallengeCard(challenge: ch),
          ),
          const SizedBox(height: 8),
        ],

        // Friends list
        _SectionHeader(
          title:
              'FRIENDS (${filteredFriends.length})',
          paddingTop: pendingTotal > 0 ? 0 : 0,
        ),
        if (filteredFriends.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'No friends yet — add someone!',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          )
        else
          ...filteredFriends.map((f) => _FriendRow(friend: f)),

        const SizedBox(height: 16),

        // Add a Friend button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.person_add_alt_1_outlined,
                size: 18),
            label: const Text('Add a Friend'),
            onPressed: () => _showAddFriendDialog(context),
          ),
        ),
      ],
    );
  }

  void _showAddFriendDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Add a Friend',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter username',
          ),
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final username = controller.text.trim();
              if (username.isNotEmpty) {
                Navigator.pop(ctx);
                context
                    .read<FriendsCubit>()
                    .sendFriendRequest(username);
              }
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending friend request card
// ---------------------------------------------------------------------------

class _PendingRequestCard extends StatelessWidget {
  final PendingRequest request;

  const _PendingRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _InitialsAvatar(username: request.username),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.username,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const Text(
                      'Wants to be your friend',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context
                      .read<FriendsCubit>()
                      .respondToRequest(request.requesterId, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size.fromHeight(36),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('ACCEPT'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context
                      .read<FriendsCubit>()
                      .respondToRequest(request.requesterId, false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(36),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('DECLINE'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending challenge card
// ---------------------------------------------------------------------------

class _PendingChallengeCard extends StatelessWidget {
  final PendingChallenge challenge;

  const _PendingChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final modeName =
        challenge.mode == 'classic' ? 'Classic' : 'Time Attack';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _InitialsAvatar(username: challenge.challengerUsername),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.challengerUsername,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Sent you a challenge · $modeName',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      AppColors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'CHALLENGE',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context
                      .read<FriendsCubit>()
                      .respondToChallenge(challenge.id, true, challenge.mode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size.fromHeight(36),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('ACCEPT'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context
                      .read<FriendsCubit>()
                      .respondToChallenge(challenge.id, false, challenge.mode),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(36),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('DECLINE'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friend row
// ---------------------------------------------------------------------------

class _FriendRow extends StatelessWidget {
  final FriendModel friend;

  const _FriendRow({required this.friend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          _InitialsAvatar(username: friend.username),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.username,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  friend.weeklyScore > 0
                      ? '${friend.weeklyScore} this week'
                      : 'No score this week',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _showChallengeSheet(context, friend),
            style: OutlinedButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('CHALLENGE'),
          ),
        ],
      ),
    );
  }

  void _showChallengeSheet(BuildContext context, FriendModel friend) {
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
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final double paddingTop;

  const _SectionHeader({required this.title, this.paddingTop = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, paddingTop, 24, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String username;

  const _InitialsAvatar({required this.username});

  @override
  Widget build(BuildContext context) {
    final initials = username.isEmpty
        ? '?'
        : username.substring(0, username.length.clamp(0, 2)).toUpperCase();
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.inputFill,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

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
