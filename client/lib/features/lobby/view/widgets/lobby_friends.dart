import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';

/// What the friends card shows instead of rows.
enum LobbyFriendsNotice { loading, error, empty, guest }

/// «بازی با دوستان» (canvas `ZLobbyA`): the player's real friends, each with a
/// real sub-line (this week's score — the canvas's head-to-head record and
/// «بهترین زنجیر» have no endpoint) and an invite button that sends a Classic
/// friend challenge. [onInvite] gets the friend; [invited] / [inviting] drive
/// the button state.
class LobbyFriendsCard extends StatelessWidget {
  /// Null → show the friends; otherwise the matching notice.
  final LobbyFriendsNotice? notice;
  final List<FriendModel> friends;
  final Set<String> invited;
  final Set<String> inviting;
  final String? errorMessage;
  final ValueChanged<FriendModel> onInvite;

  /// Retry (error), add a friend (empty) or sign in (guest).
  final VoidCallback onNoticeAction;

  const LobbyFriendsCard({
    super.key,
    required this.notice,
    required this.friends,
    required this.invited,
    required this.inviting,
    required this.onInvite,
    required this.onNoticeAction,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final notice = this.notice;
    return ChunkyBox(
      fill: z.surface,
      depth: ZGame.depthMd,
      radius: 22,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text(
                  'بازی با دوستان',
                  style: ZTypography.button.copyWith(
                    fontSize: 14,
                    height: 1.4,
                    color: z.ink,
                  ),
                ),
                if (notice == null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${toPersianDigits(friends.length)} نفر',
                    style: ZTypography.metaLabel.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: z.ink60,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (notice == null)
            for (var i = 0; i < friends.length; i++)
              _FriendRow(
                friend: friends[i],
                index: i,
                divider: i > 0,
                invited: invited.contains(friends[i].userId),
                inviting: inviting.contains(friends[i].userId),
                onInvite: () => onInvite(friends[i]),
              )
          else if (notice == LobbyFriendsNotice.loading)
            for (var i = 0; i < 3; i++) _SkeletonRow(divider: i > 0)
          else
            _Notice(
              message: switch (notice) {
                LobbyFriendsNotice.error => errorMessage ?? '',
                LobbyFriendsNotice.empty =>
                  'هنوز دوستی اضافه نکرده‌ای. دوستانت را اضافه کن تا بتوانی دعوتشان کنی.',
                _ => 'برای دعوت دوستانت اول وارد حسابت شو.',
              },
              action: switch (notice) {
                LobbyFriendsNotice.error => 'تلاش دوباره',
                LobbyFriendsNotice.empty => 'افزودن دوست',
                _ => 'ورود',
              },
              onAction: onNoticeAction,
            ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final FriendModel friend;
  final int index;
  final bool divider;
  final bool invited;
  final bool inviting;
  final VoidCallback onInvite;

  const _FriendRow({
    required this.friend,
    required this.index,
    required this.divider,
    required this.invited,
    required this.inviting,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (fill, on) = switch (index % 4) {
      0 => (z.coral, context.zs.onCoralSm),
      1 => (z.teal, z.onTeal),
      2 => (z.indigo, z.onIndigo),
      _ => (z.amber, z.onAmber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border:
            divider ? Border(top: BorderSide(color: z.wash, width: 2)) : null,
      ),
      child: Row(
        children: [
          ZDiscAvatar(
            fill: fill,
            onFill: on,
            letter: avatarInitial(friend.username, fallback: '؟'),
            size: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.button.copyWith(
                    fontSize: 14,
                    height: 1.3,
                    color: z.ink,
                  ),
                ),
                Text(
                  '${formatPersianNumber(friend.weeklyScore)} امتیاز این هفته',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: z.ink60,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _InviteButton(
            name: friend.username,
            invited: invited,
            busy: inviting,
            onTap: onInvite,
          ),
        ],
      ),
    );
  }
}

/// «دعوت به بازی» → «دعوت شد». An invite can't be withdrawn (no endpoint —
/// todo.md 2.1), so the sent state is inert rather than a toggle.
class _InviteButton extends StatelessWidget {
  final String name;
  final bool invited;
  final bool busy;
  final VoidCallback onTap;

  const _InviteButton({
    required this.name,
    required this.invited,
    required this.busy,
    required this.onTap,
  });

  static const _depth = 3.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final inert = invited || busy;
    final label = invited ? 'دعوت شد' : 'دعوت به بازی';
    final text = Text(
      label,
      maxLines: 1,
      style: ZTypography.button.copyWith(
        fontSize: 12.5,
        height: 1,
        color: inert ? z.ink60 : z.onAmber,
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child:
          inert
              ? Semantics(
                button: true,
                enabled: false,
                label: '$label؛ $name',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: _depth + ZGame.outline,
                  ),
                  child: Opacity(
                    opacity: busy ? .6 : 1,
                    child: ChunkyBox(
                      fill: z.wash,
                      depth: 0,
                      radius: 13,
                      highlight: false,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      child: text,
                    ),
                  ),
                ),
              )
              : ChunkyPressable(
                depth: _depth,
                onTap: onTap,
                semanticLabel: '$label؛ $name',
                builder:
                    (context, edge, _) => ChunkyBox(
                      fill: z.amber,
                      deep: z.amberDeep,
                      depth: edge,
                      radius: 13,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      child: text,
                    ),
              ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final bool divider;

  const _SkeletonRow({required this.divider});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: z.wash,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border:
            divider ? Border(top: BorderSide(color: z.wash, width: 2)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: z.wash, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [bar(96, 12), const SizedBox(height: 7), bar(64, 10)],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;
  final String action;
  final VoidCallback onAction;

  const _Notice({
    required this.message,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.6,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 10),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: ZDialogButton.secondary(
              label: action,
              onTap: onAction,
              height: 46,
              radius: 16,
              depth: 4,
            ),
          ),
        ],
      ),
    );
  }
}
