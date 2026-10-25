import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';

/// Wraps a name in a bidi isolate so a Latin username can't reorder the
/// Persian around it (semantics labels, toasts, dialog titles).
String isolate(String name) => '\u2068$name\u2069';

/// The avatar of a Friends-tab row: a coloured disc with the initial (or the
/// premium avatar image), the colour cycling through the four accents the way
/// the canvas hues its friends.
class FriendDisc extends StatelessWidget {
  final String name;
  final int index;
  final double size;
  final String? avatarId;

  const FriendDisc({
    super.key,
    required this.name,
    required this.index,
    required this.size,
    this.avatarId,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (fill, on) = switch (index % 4) {
      0 => (z.teal, z.onTeal),
      1 => (z.coral, context.zs.onCoralSm),
      2 => (z.indigo, z.onIndigo),
      _ => (z.amber, z.onAmber),
    };
    return ExcludeSemantics(
      child: ZDiscAvatar(
        fill: fill,
        onFill: on,
        letter: avatarInitial(name, fallback: '؟'),
        size: size,
        avatarId: avatarId,
      ),
    );
  }
}

/// «درخواست‌ها» / «دوستان من» — the card heading: a 14sp title with an
/// optional trailing count (a coral badge or a plain «N نفر»).
class FriendsCardHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const FriendsCardHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZTypography.button.copyWith(
                  fontSize: 14,
                  height: 1.4,
                  color: context.z.ink,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

/// A row divider: the canvas's 2px `wash` rule above every row but the first.
BoxDecoration rowDecoration(BuildContext context, {required bool divider}) =>
    BoxDecoration(
      border:
          divider
              ? Border(top: BorderSide(color: context.z.wash, width: 2))
              : null,
    );

enum FriendsGlyph { addFriend, accept, decline }

/// The 44dp square buttons of the Friends tab: «افزودن دوست» (teal, raised),
/// «پذیرفتن» (teal) and «رد کردن» (neutral). Canvas `ZFriendsA`.
class FriendsGlyphButton extends StatelessWidget {
  final FriendsGlyph glyph;
  final String semanticLabel;
  final VoidCallback onTap;

  const FriendsGlyphButton({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final raised = glyph == FriendsGlyph.addFriend;
    final teal = glyph != FriendsGlyph.decline;
    final stroke = svgHex(teal ? z.onTeal : z.ink);
    final svg = switch (glyph) {
      FriendsGlyph.addFriend =>
        '<svg viewBox="0 0 24 24" fill="none" stroke="$stroke" stroke-width="3" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6M19 8v6M16 11h6"/></svg>',
      FriendsGlyph.accept =>
        '<svg viewBox="0 0 24 24" fill="none" stroke="$stroke" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7"/></svg>',
      FriendsGlyph.decline =>
        '<svg viewBox="0 0 24 24" fill="none" stroke="$stroke" stroke-width="3.6" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    };
    final size = glyph == FriendsGlyph.decline ? 16.0 : 20.0;
    return ChunkyPressable(
      depth: raised ? 4 : ZGame.depthSm,
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder:
          (context, depth, _) => ChunkyBox(
            fill: teal ? z.teal : z.surface,
            deep: raised ? z.tealDeep : null,
            depth: depth,
            radius: 14,
            highlight: teal,
            width: ZGame.gameBackButton,
            height: ZGame.gameBackButton,
            alignment: Alignment.center,
            child: SvgPicture.string(svg, width: size, height: size),
          ),
    );
  }
}
