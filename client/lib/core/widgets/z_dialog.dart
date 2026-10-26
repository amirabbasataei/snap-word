import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/motion.dart';

/// Shows [builder]'s content as a centred "chunky" dialog over the `scrim`
/// token (canvas turn 8 `ZExitConfirm`, turn 7 level picker). Every modal in
/// the app that is not a screen goes through here, so the frame, backdrop and
/// entrance are the same everywhere.
///
/// The entrance drops 48px with the canvas spring (`dropin`, 520ms); under
/// reduced motion it is a 200ms fade. Tapping the scrim dismisses when
/// [barrierDismissible] (the exit dialog treats that as "stay").
Future<T?> showZDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String barrierLabel = 'بستن',
}) {
  final reduced = homeReducedMotion(context);
  final direction = Directionality.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: context.zs.scrim,
    transitionDuration:
        reduced ? ZGameMotion.dialogEnterReduced : ZGameMotion.dialogEnter,
    pageBuilder:
        (context, _, _) => Directionality(
          textDirection: direction,
          // A dialog with a text field must stay above the soft keyboard: the
          // card centres in what is left and scrolls when that is too short.
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZGame.dialogInset,
                    vertical: ZGame.dialogInset,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ZGame.dialogMaxWidth,
                    ),
                    // Material gives descendants a text style and ink context
                    // without painting anything.
                    child: Material(
                      type: MaterialType.transparency,
                      // A Builder so [builder]'s context sits below the
                      // Directionality above.
                      child: Builder(builder: builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    transitionBuilder: (context, animation, _, child) {
      if (reduced) return FadeTransition(opacity: animation, child: child);
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final opening = animation.status != AnimationStatus.reverse;
          final fade = Curves.easeOut.transform(
            (animation.value / .4).clamp(0.0, 1.0),
          );
          final drop =
              opening
                  ? _spring.transform(animation.value)
                  : Curves.easeIn.transform(animation.value);
          return Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(0, -48 * (1 - drop)),
              child: child,
            ),
          );
        },
      );
    },
  );
}

/// The canvas spring `cubic-bezier(.34,1.56,.64,1)`.
const _spring = Cubic(.34, 1.56, .64, 1);

/// The dialog frame: surface card with a 3px outline, r28 and a solid 6px
/// edge. An optional [mascot] stands on the card's top edge.
class ZDialogCard extends StatelessWidget {
  final Widget? mascot;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;
  final Widget child;

  const ZDialogCard({
    super.key,
    this.mascot,
    this.padding,
    this.semanticLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final hasMascot = mascot != null;
    final card = ChunkyBox(
      fill: z.surface,
      depth: ZGame.dialogDepth,
      radius: ZGame.dialogRadius,
      highlight: false,
      padding: padding ?? EdgeInsets.fromLTRB(16, hasMascot ? 48 : 16, 16, 16),
      child: child,
    );
    final framed =
        hasMascot
            ? Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: ZGame.dialogMascotLift),
                  child: card,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: Center(child: mascot)),
                ),
              ],
            )
            : card;
    return Semantics(
      container: true,
      scopesRoute: true,
      namesRoute: semanticLabel != null,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Padding(
        // Room for the solid edge so it is never clipped by the scroll view.
        padding: const EdgeInsets.only(bottom: ZGame.dialogDepth),
        child: framed,
      ),
    );
  }
}

enum ZDialogAccent { teal, indigo, amber, coral }

/// A dialog button in the canvas's chunky style. [ZDialogButton.primary] is
/// the filled accent button (default: 58 tall, r20, 5px edge);
/// [ZDialogButton.secondary] is the neutral surface button with an optional
/// coloured label and leading icon (50 tall, r18, 4px edge, 16 pt label).
class ZDialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool _primary;
  final ZDialogAccent accent;
  final double? height;
  final double? radius;
  final double? depth;
  final double? fontSize;

  /// Secondary only: label colour (defaults to `ink`).
  final Color? labelColor;

  /// Leading glyph, drawn by the caller in the colour it needs.
  final Widget? icon;

  const ZDialogButton.primary({
    super.key,
    required this.label,
    required this.onTap,
    this.accent = ZDialogAccent.teal,
    this.height,
    this.radius,
    this.depth,
    this.fontSize,
    this.icon,
  }) : _primary = true,
       labelColor = null;

  const ZDialogButton.secondary({
    super.key,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.icon,
    this.height,
    this.radius,
    this.depth,
    this.fontSize,
  }) : _primary = false,
       accent = ZDialogAccent.teal;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    if (_primary) {
      final (fill, deep, on) = switch (accent) {
        ZDialogAccent.teal => (z.teal, z.tealDeep, z.onTeal),
        ZDialogAccent.indigo => (z.indigo, z.indigoDeep, z.onIndigo),
        ZDialogAccent.amber => (z.amber, z.amberDeep, z.onAmber),
        ZDialogAccent.coral => (z.coral, z.coralDeep, z.onCoral),
      };
      final d = depth ?? ZGame.depthMd;
      return ChunkyPressable(
        depth: d,
        onTap: onTap,
        semanticLabel: label,
        builder:
            (context, depth, pressed) => ChunkyBox(
              fill: fill,
              deep: deep,
              depth: depth,
              radius: radius ?? ZGame.dialogPrimaryRadius,
              height: height ?? ZGame.dialogPrimaryHeight,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 8)],
                  // The pressable already announces [label]; the visible text
                  // would make a screen reader say it twice.
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: ZTypography.button.copyWith(
                        fontSize: fontSize ?? 19,
                        height: 1,
                        color: on,
                        shadows: [
                          Shadow(color: deep, offset: const Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      );
    }
    final ink = labelColor ?? z.ink;
    return ChunkyPressable(
      depth: depth ?? ZGame.depthSm + 1,
      onTap: onTap,
      semanticLabel: label,
      builder:
          (context, edge, pressed) => ChunkyBox(
            fill: z.surface,
            deep: zs.tileDeep,
            depth: edge,
            radius: radius ?? ZGame.dialogSecondaryRadius,
            height: height ?? ZGame.dialogSecondaryHeight,
            highlight: false,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 8)],
                ExcludeSemantics(
                  child: Text(
                    label,
                    style: ZTypography.button.copyWith(
                      fontSize: fontSize ?? 16,
                      height: 1,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
