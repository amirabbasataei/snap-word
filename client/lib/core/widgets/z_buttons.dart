import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

enum ZAccentColor { indigo, teal, amber, coral, ink }

(Color, Color, Color) _accentColorsFor(ZColors z, ZAccentColor accent) {
  switch (accent) {
    case ZAccentColor.indigo:
      return (z.indigo, z.onIndigo, z.indigoDeep);
    case ZAccentColor.teal:
      return (z.teal, z.onTeal, z.tealDeep);
    case ZAccentColor.amber:
      return (z.amber, z.onAmber, z.amberDeep);
    case ZAccentColor.coral:
      return (z.coral, z.onCoral, z.coralDeep);
    // Dark/light-inverting fill used for ZLogin's primary CTA — same pairing
    // the canvas uses for the "player's own" hero surface (ink/paper/inkSurfaceDeep).
    case ZAccentColor.ink:
      return (z.ink, z.paper, z.inkSurfaceDeep);
  }
}

/// Primary call-to-action button: solid accent fill, `0 4px 0 accent-deep`
/// edge. Pressed state removes the offset and translates Y +3 (90ms).
class AccentButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final ZAccentColor accent;
  final IconData? icon;

  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.accent = ZAccentColor.indigo,
    this.icon,
  });

  @override
  State<AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<AccentButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final disabled = widget.onPressed == null;
    final (bg, onColor, deep) = _accentColorsFor(z, widget.accent);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          _pressed ? ZElevation.pressedTranslateY : 0,
          0,
        ),
        constraints: const BoxConstraints(
          minHeight: ZHitTarget.buttonMin,
          maxHeight: ZHitTarget.buttonMax,
        ),
        padding: const EdgeInsets.symmetric(horizontal: ZSpacing.xl),
        decoration: BoxDecoration(
          color: disabled ? z.wash : bg,
          borderRadius: BorderRadius.circular(ZRadius.tileMax),
          boxShadow: (disabled || _pressed)
              ? null
              : ZElevation.solidEdge(deep, depth: ZElevation.buttonDepth),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(
                widget.icon,
                size: 18,
                color: disabled ? z.ink40 : onColor,
              ),
              const SizedBox(width: ZSpacing.sm),
            ],
            Text(
              widget.label,
              style: ZTypography.button.copyWith(
                color: disabled ? z.ink40 : onColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary button: `surface` fill, `line` border and edge, `ink` label.
/// Same press animation as [AccentButton].
class NeutralButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const NeutralButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  State<NeutralButton> createState() => _NeutralButtonState();
}

class _NeutralButtonState extends State<NeutralButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final disabled = widget.onPressed == null;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          _pressed ? ZElevation.pressedTranslateY : 0,
          0,
        ),
        constraints: const BoxConstraints(
          minHeight: ZHitTarget.buttonMin,
          maxHeight: ZHitTarget.buttonMax,
        ),
        padding: const EdgeInsets.symmetric(horizontal: ZSpacing.xl),
        decoration: BoxDecoration(
          color: z.surface,
          borderRadius: BorderRadius.circular(ZRadius.tileMax),
          border: Border.all(color: z.line),
          boxShadow: (disabled || _pressed)
              ? null
              : ZElevation.solidEdge(z.line, depth: ZElevation.buttonDepth),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 18, color: disabled ? z.ink40 : z.ink),
              const SizedBox(width: ZSpacing.sm),
            ],
            Text(
              widget.label,
              style: ZTypography.button.copyWith(
                color: disabled ? z.ink40 : z.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
