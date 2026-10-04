import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';

/// Actionable invitations behind the home inbox icon: friend requests and
/// friend challenges. Claimable coin prizes live on the rewards screen.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    getIt<MessagesCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZSpacing.screenGutter,
                ZSpacing.lg,
                ZSpacing.screenGutter,
                ZSpacing.md,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.arrow_back_rounded, color: z.ink),
                  ),
                  const SizedBox(width: ZSpacing.sm),
                  Text(
                    'پیام‌ها',
                    style: ZTypography.screenTitle.copyWith(color: z.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<MessagesCubit, MessagesState>(
                bloc: getIt<MessagesCubit>(),
                builder: (context, state) {
                  if (state.count == 0) {
                    return Center(
                      child:
                          state.loading
                              ? CircularProgressIndicator(color: z.indigo)
                              : Text(
                                'پیامی نداری',
                                style: ZTypography.body.copyWith(
                                  color: z.ink40,
                                ),
                              ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      ZSpacing.screenGutter,
                      0,
                      ZSpacing.screenGutter,
                      ZSpacing.xl,
                    ),
                    children: [
                      for (final r in state.requests) ...[
                        _MessageTile(
                          name: r.username,
                          accent: ZAccent.amber,
                          title: r.username,
                          body: 'می‌خواهد دوست تو شود',
                          onAccept: () => _respondRequest(r, true),
                          onDecline: () => _respondRequest(r, false),
                        ),
                        const SizedBox(height: ZSpacing.md),
                      ],
                      for (final c in state.challenges) ...[
                        _MessageTile(
                          name: c.challengerUsername,
                          accent: ZAccent.coral,
                          title: c.challengerUsername,
                          body: 'تو را به یک بازی کلاسیک چالش کرد',
                          onAccept: () => _respondChallenge(c, true),
                          onDecline: () => _respondChallenge(c, false),
                        ),
                        const SizedBox(height: ZSpacing.md),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _respondRequest(PendingRequest r, bool accept) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await getIt<MessagesCubit>().respondToRequest(r.requesterId, accept);
    } on FriendsException {
      ZToast.showOn(
        overlay,
        'مشکلی پیش آمد، دوباره تلاش کن',
        kind: ZToastKind.error,
      );
    }
  }

  Future<void> _respondChallenge(PendingChallenge c, bool accept) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final roomId = await getIt<MessagesCubit>().respondToChallenge(
        c.id,
        accept,
      );
      if (roomId != null && mounted) {
        context.push(
          '/game',
          extra: GameRouteArgs(
            mode: c.mode,
            opponentType: 'multiplayer',
            roomId: roomId,
          ),
        );
      }
    } on FriendsException {
      // Expired or answered elsewhere → resync instead of a dead-end error.
      await getIt<MessagesCubit>().refresh();
      ZToast.showOn(
        overlay,
        'این چالش دیگر معتبر نیست',
        kind: ZToastKind.error,
      );
    }
  }
}

class _MessageTile extends StatefulWidget {
  final String name;
  final ZAccent accent;
  final String title;
  final String body;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  const _MessageTile({
    required this.name,
    required this.accent,
    required this.title,
    required this.body,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final initial =
        widget.name.isEmpty ? '؟' : widget.name.substring(0, 1).toUpperCase();
    return SolidCard(
      padding: const EdgeInsets.all(ZSpacing.lg),
      radius: ZRadius.cardMax,
      child: Row(
        children: [
          LetterTile(
            letter: initial,
            size: 34,
            accent: widget.accent,
            radius: 11,
            fontSize: 15,
          ),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: ZTypography.cardTitle.copyWith(color: z.ink),
                ),
                Text(
                  widget.body,
                  style: ZTypography.metaLabel.copyWith(color: z.ink40),
                ),
              ],
            ),
          ),
          _PillAction(
            label: 'تأیید',
            bg: z.teal,
            fg: z.onTeal,
            onTap: _busy ? null : () => _run(widget.onAccept),
          ),
          const SizedBox(width: 6),
          _PillAction(
            label: 'رد',
            bg: z.paper,
            fg: z.ink40,
            onTap: _busy ? null : () => _run(widget.onDecline),
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
  final VoidCallback? onTap;

  const _PillAction({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ZRadius.chip),
        ),
        child: Text(
          label,
          style: ZTypography.metaLabel.copyWith(
            color: fg,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
