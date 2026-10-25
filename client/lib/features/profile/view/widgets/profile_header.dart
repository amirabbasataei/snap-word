import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';

/// The top of the profile (canvas `ZProfileA`): the player's disc inside a
/// ring that fills with the level's XP, the level badge hanging under it, the
/// name and a title chip.
///
/// Corner slots: the coin balance at the start (tap → buy coins) and the
/// rename pencil at the end — the canvas draws a gear and a pencil there; the
/// gear has no screen behind it, so the live coin balance takes its place.
/// Guests have no level, balance or rename: the ring is empty, the slots are
/// blank and the chip says they are playing as a guest.
class ProfileHeader extends StatelessWidget {
  final String username;
  final bool signedIn;
  final int level;
  final double xpFraction;
  final int xpInLevel;
  final int xpForNext;
  final String? avatarId;
  final bool isPremium;
  final int coins;
  final VoidCallback? onCoinsTap;
  final VoidCallback? onEdit;

  const ProfileHeader({
    super.key,
    required this.username,
    required this.signedIn,
    required this.level,
    required this.xpFraction,
    required this.xpInLevel,
    required this.xpForNext,
    required this.avatarId,
    required this.isPremium,
    required this.coins,
    this.onCoinsTap,
    this.onEdit,
  });

  static const ringSize = 112.0;
  static const discSize = 88.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final name = signedIn ? username : 'مهمان';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child:
                      signedIn
                          ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1.3,
                              child: Padding(
                                // The coin overhangs the pill's start edge.
                                padding: const EdgeInsetsDirectional.only(
                                  start: 8,
                                ),
                                child: ZHudCoinPill(
                                  coins: coins,
                                  onTap: onCoinsTap,
                                ),
                              ),
                            ),
                          )
                          : const SizedBox(width: 44, height: 44),
                ),
              ),
              _Avatar(
                name: name,
                signedIn: signedIn,
                level: level,
                xpFraction: xpFraction,
                xpInLevel: xpInLevel,
                xpForNext: xpForNext,
                avatarId: avatarId,
              ),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  child:
                      signedIn && onEdit != null
                          ? ProfileGlyphButton(
                            semanticLabel: 'ویرایش نام کاربری',
                            onTap: onEdit!,
                            svg: pencilSvg,
                          )
                          : const SizedBox(width: 44, height: 44),
                ),
              ),
            ],
          ),
        ),
        // The level badge hangs 12 below the ring.
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: ZTypography.screenTitle.copyWith(
                      fontSize: 22,
                      height: 1.2,
                      color: z.ink,
                    ),
                  ),
                ),
              ),
              if (signedIn && isPremium) ...[
                const SizedBox(width: 6),
                ProfileCrown(
                  size: 22,
                  fill: z.amber,
                  stroke: z.amberDeep,
                  semanticLabel: 'اشتراک ویژه',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        signedIn
            ? _Chip(
              label: GameConstants.levelTitle(level),
              fill: z.inkSurface,
              textColor: z.onInkSurface,
              outlined: false,
            )
            : _Chip(
              label: 'در حال بازی به‌صورت مهمان',
              fill: z.surface,
              textColor: z.ink,
              outlined: true,
            ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color fill;
  final Color textColor;
  final bool outlined;

  const _Chip({
    required this.label,
    required this.fill,
    required this.textColor,
    required this.outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border:
            outlined ? Border.all(color: context.zs.outline, width: 2) : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: ZTypography.button.copyWith(
          fontSize: 12.5,
          height: 1.5,
          color: textColor,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool signedIn;
  final int level;
  final double xpFraction;
  final int xpInLevel;
  final int xpForNext;
  final String? avatarId;

  const _Avatar({
    required this.name,
    required this.signedIn,
    required this.level,
    required this.xpFraction,
    required this.xpInLevel,
    required this.xpForNext,
    required this.avatarId,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final f = xpFraction.clamp(0.0, 1.0);
    final ring = Container(
      width: ProfileHeader.ringSize,
      height: ProfileHeader.ringSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: zs.outline, width: ZGame.outline),
        // CSS `conic-gradient(amber 0 f, wash 0)`: clockwise from the top.
        gradient: SweepGradient(
          colors: [
            signedIn ? z.amber : z.wash,
            signedIn ? z.amber : z.wash,
            z.wash,
            z.wash,
          ],
          stops: [0, f, f, 1],
          transform: const GradientRotation(-math.pi / 2),
        ),
        boxShadow: [BoxShadow(color: zs.outline, offset: const Offset(0, 5))],
      ),
      child: ExcludeSemantics(
        child: ZDiscAvatar.me(
          context,
          letter: avatarInitial(name, fallback: '؟'),
          size: ProfileHeader.discSize,
          avatarId: signedIn ? avatarId : null,
        ),
      ),
    );

    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          signedIn
              ? 'سطح ${toPersianDigits(level)}؛ '
                  '${formatPersianNumber(xpInLevel)} از '
                  '${formatPersianNumber(xpForNext)} امتیاز'
              : 'مهمان',
      child: SizedBox(
        width: ProfileHeader.ringSize,
        height: ProfileHeader.ringSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ring,
            if (signedIn)
              PositionedDirectional(
                bottom: -12,
                start: (ProfileHeader.ringSize - 40) / 2,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: ChunkyBox(
                    fill: z.amber,
                    depth: ZGame.depthSm,
                    radius: 10,
                    width: 40,
                    height: 30,
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        toPersianDigits(level),
                        style: ZTypography.button.copyWith(
                          fontSize: 15,
                          color: z.onAmber,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
