import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// Asks the player to confirm a friend challenge before it is sent (canvas
/// turn 9, `ZInviteConfirm`, frames 9a/9b). Resolves to true when the player
/// taps «بفرست»; closing, «بی‌خیال» and a tap on the scrim all resolve to
/// false. Classic is the only mode, so the caller sends `'classic'`.
Future<bool> showFriendChallengeDialog(
  BuildContext context, {
  required String friendUsername,
}) async {
  final auth = getIt<AuthCubit>().state;
  final me = auth is AuthAuthenticated ? auth.username : null;
  final sent = await showZDialog<bool>(
    context,
    builder:
        (dialogContext) => FriendChallengeDialog(
          friendUsername: friendUsername,
          myInitial: avatarInitial(me),
          onConfirm: () => Navigator.of(dialogContext).pop(true),
          onCancel: () => Navigator.of(dialogContext).pop(false),
        ),
  );
  return sent ?? false;
}

class FriendChallengeDialog extends StatelessWidget {
  final String friendUsername;
  final String myInitial;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const FriendChallengeDialog({
    super.key,
    required this.friendUsername,
    required this.myInitial,
    required this.onConfirm,
    required this.onCancel,
  });

  /// «X را به بازی دعوت کنی؟». The name goes in a bidi isolate so a Latin
  /// username cannot reorder the Persian around it.
  static String titleFor(String friendUsername) =>
      '\u2068$friendUsername\u2069 را به بازی دعوت کنی؟';

  // Canvas: «تا ۲ دقیقه منتظر جوابش می‌مونی» — the challenge actually stays
  // open for 24h (the 2 minutes is how long a room waits once it is accepted).
  static final body =
      'براش اعلان می‌ره و تا ${toPersianDigits(GameConstants.challengeValidHours)} '
      'ساعت وقت داره جواب بده.';

  // Canvas: «وقتی کم می‌شه که دعوت رو قبول کنه» — the fee is taken when both
  // players are in the room and the match starts.
  static const feeNote = 'سکه وقتی کم می‌شه که بازی شروع بشه، نه همین حالا.';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final title = titleFor(friendUsername);
    return ZDialogCard(
      semanticLabel: title,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Who plays whom, up front, so a mis-tap is obvious. The friend is
          // coral, as the opponent is on the game screens.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _Pair(
              me: myInitial,
              friend: nameInitial(friendUsername),
              friendFill: z.coral,
              friendInk: zs.onCoralSm,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: ZTypography.screenTitle.copyWith(
              fontSize: 21,
              height: 1.35,
              color: z.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.65,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 14),
          const _FeeTiles(),
          const SizedBox(height: 14),
          Text(
            feeNote,
            textAlign: TextAlign.center,
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 10,
                child: ZDialogButton.secondary(
                  label: 'بی‌خیال',
                  onTap: onCancel,
                  height: 54,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 16,
                child: ZDialogButton.primary(
                  label: 'بفرست',
                  onTap: onConfirm,
                  height: 54,
                  radius: 18,
                  depth: ZGame.depthSm + 1,
                  fontSize: 17,
                  icon: SvgPicture.string(
                    '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.onTeal)}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M21 3L10 14M21 3l-7 18-4-7-7-4z"/></svg>',
                    width: 18,
                    height: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two 60px discs joined by an amber chain link.
class _Pair extends StatelessWidget {
  final String me;
  final String friend;
  final Color friendFill;
  final Color friendInk;

  const _Pair({
    required this.me,
    required this.friend,
    required this.friendFill,
    required this.friendInk,
  });

  static const _disc = 60.0;
  static const _linkWidth = 44.0;
  static const _overlap = 6.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    Widget disc(String letter, Color fill, Color ink) => ChunkyBox(
      fill: fill,
      circle: true,
      depth: ZGame.depthSm + 1,
      width: _disc,
      height: _disc,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: ZTypography.button.copyWith(
          fontSize: 26,
          height: 1,
          color: ink,
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        height: _disc + ZGame.depthSm + 1,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // Behind the discs, which cover the link's ends.
            Positioned(
              top: (_disc - 14) / 2,
              child: CustomPaint(
                size: const Size(_linkWidth, 14),
                painter: _LinkPainter(
                  fill: z.amber,
                  outline: context.zs.outline,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                disc(me, z.indigo, z.onIndigo),
                // 44px link overlapping each disc by 6px.
                const SizedBox(width: _linkWidth - 2 * _overlap),
                disc(friend, friendFill, friendInk),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal chain link: 5px band in [fill], outlined 2.5px outside and
/// filled in the middle (canvas: border 5, `0 0 0 2.5px outline`, inset 2.5px).
class _LinkPainter extends CustomPainter {
  final Color fill;
  final Color outline;

  const _LinkPainter({required this.fill, required this.outline});

  @override
  void paint(Canvas canvas, Size size) {
    const ring = 2.5;
    const band = 5.0;
    final c = size.center(Offset.zero);
    RRect pill(double inset, {double grow = 0}) => RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: c,
        width: size.width + 2 * grow - 2 * inset,
        height: size.height + 2 * grow - 2 * inset,
      ),
      const Radius.circular(999),
    );
    canvas.drawRRect(pill(0, grow: ring), Paint()..color = outline);
    canvas.drawRRect(pill(0), Paint()..color = fill);
    canvas.drawRRect(pill(band), Paint()..color = outline);
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.fill != fill || old.outline != outline;
}

/// «ورودی ۲۰ سکه ← جایزهٔ برنده ۴۰ سکه» — the same two tiles as the lobby.
class _FeeTiles extends StatelessWidget {
  const _FeeTiles();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Row(
      children: [
        Expanded(
          child: _Tile(
            label: 'ورودی',
            value: '${toPersianDigits(GameConstants.entryFeeCoins)} سکه',
            fill: z.wash,
            ink: z.ink,
            sub: z.ink60,
            highlight: false,
          ),
        ),
        const SizedBox(width: 8),
        SvgPicture.string(
          '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.ink)}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5M11 6l-6 6 6 6"/></svg>',
          width: 20,
          height: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            label: 'جایزهٔ برنده',
            value: '${toPersianDigits(GameConstants.entryFeePot)} سکه',
            fill: z.amber,
            ink: z.onAmber,
            sub: z.onAmber,
            highlight: true,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color fill;
  final Color ink;
  final Color sub;
  final bool highlight;

  const _Tile({
    required this.label,
    required this.value,
    required this.fill,
    required this.ink,
    required this.sub,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: fill,
      depth: 0,
      radius: 16,
      highlight: highlight,
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // The coin: an amber disc with a ring.
          ChunkyBox(
            fill: z.amber,
            circle: true,
            depth: 0,
            highlight: false,
            borderWidth: ZGame.outlineInner,
            width: 30,
            height: 30,
            alignment: Alignment.center,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: z.amberDeep, width: 2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: sub,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.button.copyWith(
                    fontSize: 16,
                    height: 1.2,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
