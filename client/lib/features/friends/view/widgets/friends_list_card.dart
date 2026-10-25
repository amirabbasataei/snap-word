import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_invite_button.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/friends/view/widgets/friends_parts.dart';

/// «دوستان من» (canvas `ZFriendsA`): the player's real friends, each with an
/// amber «دعوت به بازی» that sends a Classic challenge (after the confirm
/// dialog the caller shows). The sub-line is this week's score — the canvas's
/// «با هم: ۴ برد · ۲ باخت» and «بهترین زنجیر ۲۹» have no endpoint
/// (todo.md 2.6). A long press on a row asks to remove the friend; the canvas
/// has no remove control, so a one-line hint says so.
class FriendsListCard extends StatelessWidget {
  /// The friends to list (already filtered by the search).
  final List<FriendModel> friends;

  /// How many friends the player has in all — tells «no friends yet» from «no
  /// match for the search».
  final int totalFriends;
  final Set<String> invited;
  final ValueChanged<FriendModel> onInvite;
  final ValueChanged<FriendModel> onRemove;
  final VoidCallback onAddFriend;

  const FriendsListCard({
    super.key,
    required this.friends,
    required this.totalFriends,
    required this.invited,
    required this.onInvite,
    required this.onRemove,
    required this.onAddFriend,
  });

  static const removeHint = 'برای حذف یک دوست، روی نامش نگه دار';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
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
          FriendsCardHeader(
            title: 'دوستان من',
            trailing:
                totalFriends == 0
                    ? null
                    : Text(
                      '${toPersianDigits(friends.length)} نفر',
                      style: ZTypography.metaLabel.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: z.ink60,
                      ),
                    ),
          ),
          if (totalFriends == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: ZEmptyState(
                title: 'هنوز دوستی نداری',
                body:
                    'نام کاربری دقیق دوستت را وارد کن، یا کد دعوتت را برایش بفرست.',
                actionLabel: 'افزودن دوست',
                onAction: onAddFriend,
              ),
            )
          else if (friends.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: ZEmptyState(
                mood: ZMascotMood.surprised,
                mascotSize: 72,
                title: 'نتیجه‌ای پیدا نشد',
                body: 'دوستی با این نام نداری.',
              ),
            )
          else ...[
            for (var i = 0; i < friends.length; i++)
              _FriendRow(
                friend: friends[i],
                index: i,
                divider: i > 0,
                invited: invited.contains(friends[i].userId),
                onInvite: () => onInvite(friends[i]),
                onRemove: () => onRemove(friends[i]),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                removeHint,
                textAlign: TextAlign.center,
                style: ZTypography.metaLabel.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: z.ink60,
                ),
              ),
            ),
          ],
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
  final VoidCallback onInvite;
  final VoidCallback onRemove;

  const _FriendRow({
    required this.friend,
    required this.index,
    required this.divider,
    required this.invited,
    required this.onInvite,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'حذف از دوستان'): onRemove,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onRemove,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: rowDecoration(context, divider: divider),
          child: Row(
            children: [
              FriendDisc(
                name: friend.username,
                index: index,
                size: 42,
                avatarId: friend.avatarId,
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
                      friend.weeklyScore > 0
                          ? '${formatPersianNumber(friend.weeklyScore)} امتیاز این هفته'
                          : 'بدون امتیاز این هفته',
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
              ZInviteButton(
                name: friend.username,
                invited: invited,
                busy: false,
                onTap: onInvite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
