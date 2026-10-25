import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/friends/view/widgets/friends_parts.dart';

/// «درخواست‌ها» (canvas `ZFriendsA`): friend requests and friend challenges
/// waiting for an answer, each with a teal ✓ and a neutral ✕. The sub-lines
/// are the real ones («می‌خواهد دوست تو شود», «چالش فرستاد · کلاسیک»); the
/// canvas's «۳ دوست مشترک» / «با کد دعوت تو آمده» have no data behind them.
class FriendsRequestsCard extends StatelessWidget {
  final List<PendingRequest> requests;
  final List<PendingChallenge> challenges;
  final ValueChanged<PendingRequest> onAcceptRequest;
  final ValueChanged<PendingRequest> onDeclineRequest;
  final ValueChanged<PendingChallenge> onAcceptChallenge;
  final ValueChanged<PendingChallenge> onDeclineChallenge;

  const FriendsRequestsCard({
    super.key,
    required this.requests,
    required this.challenges,
    required this.onAcceptRequest,
    required this.onDeclineRequest,
    required this.onAcceptChallenge,
    required this.onDeclineChallenge,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final total = requests.length + challenges.length;
    return ChunkyBox(
      fill: z.surface,
      depth: 4,
      radius: 20,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FriendsCardHeader(
            title: 'درخواست‌ها',
            trailing: _CountBadge(count: total),
          ),
          for (var i = 0; i < requests.length; i++)
            _InboxRow(
              name: requests[i].username,
              sub: 'می‌خواهد دوست تو شود',
              index: i,
              divider: i > 0,
              acceptLabel:
                  'پذیرفتن درخواست دوستی ${isolate(requests[i].username)}',
              declineLabel: 'رد درخواست دوستی ${isolate(requests[i].username)}',
              onAccept: () => onAcceptRequest(requests[i]),
              onDecline: () => onDeclineRequest(requests[i]),
            ),
          for (var i = 0; i < challenges.length; i++)
            _InboxRow(
              name: challenges[i].challengerUsername,
              sub: 'چالش فرستاد · کلاسیک',
              index: requests.length + i,
              divider: requests.isNotEmpty || i > 0,
              acceptLabel:
                  'پذیرفتن چالش ${isolate(challenges[i].challengerUsername)}',
              declineLabel:
                  'رد چالش ${isolate(challenges[i].challengerUsername)}',
              onAccept: () => onAcceptChallenge(challenges[i]),
              onDecline: () => onDeclineChallenge(challenges[i]),
            ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      label: '${toPersianDigits(count)} مورد',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.coral,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          toPersianDigits(count),
          style: ZTypography.button.copyWith(
            fontSize: 12,
            height: 1.45,
            color: context.zs.onCoralSm,
          ),
        ),
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  final String name;
  final String sub;
  final int index;
  final bool divider;
  final String acceptLabel;
  final String declineLabel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InboxRow({
    required this.name,
    required this.sub,
    required this.index,
    required this.divider,
    required this.acceptLabel,
    required this.declineLabel,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: rowDecoration(context, divider: divider),
      child: Row(
        children: [
          // Requests start on coral, as the canvas draws them.
          FriendDisc(name: name, index: index + 1, size: 38),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.button.copyWith(
                    fontSize: 14,
                    height: 1.3,
                    color: z.ink,
                  ),
                ),
                Text(
                  sub,
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
          const SizedBox(width: 8),
          FriendsGlyphButton(
            glyph: FriendsGlyph.accept,
            semanticLabel: acceptLabel,
            onTap: onAccept,
          ),
          const SizedBox(width: ZGame.depthSm + 2),
          FriendsGlyphButton(
            glyph: FriendsGlyph.decline,
            semanticLabel: declineLabel,
            onTap: onDecline,
          ),
        ],
      ),
    );
  }
}
