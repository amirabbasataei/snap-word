import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

/// The mascot-led input dialog of canvas `ZDialogs` (14a invite code, 14b
/// username): pill, title, body, a [panel] on `wash` holding the field, a
/// filled primary button and an optional neutral one. Both dialogs drive it
/// with their own state; this only draws the frame.
class ZFormDialog extends StatelessWidget {
  final ZMascotMood mood;
  final String pillText;
  final ZDialogAccent pillAccent;
  final String title;
  final String body;

  /// Content of the `wash` panel under the text; null for none (success).
  final Widget? panel;
  final String primaryLabel;
  final ZDialogAccent primaryAccent;

  /// Null draws the muted, edge-less disabled button.
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const ZFormDialog({
    super.key,
    required this.mood,
    required this.pillText,
    required this.pillAccent,
    required this.title,
    required this.body,
    this.panel,
    required this.primaryLabel,
    required this.primaryAccent,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZDialogCard(
      semanticLabel: title,
      mascot: ZMascot(mood: mood, size: ZGame.dialogMascotSize, shadow: false),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _Pill(text: pillText, accent: pillAccent)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: ZTypography.screenTitle.copyWith(
                fontSize: 22,
                height: 1.3,
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
            if (panel != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: z.wash,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: panel,
              ),
            ],
            const SizedBox(height: 16),
            if (onPrimary == null)
              _DisabledPrimary(label: primaryLabel)
            else
              ZDialogButton.primary(
                label: primaryLabel,
                onTap: onPrimary,
                accent: primaryAccent,
              ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 12),
              ZDialogButton.secondary(
                label: secondaryLabel!,
                onTap: onSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final ZDialogAccent accent;

  const _Pill({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (fill, on) = switch (accent) {
      ZDialogAccent.teal => (z.teal, z.onTeal),
      ZDialogAccent.indigo => (z.indigo, z.onIndigo),
      ZDialogAccent.amber => (z.amber, z.onAmber),
      ZDialogAccent.coral => (z.coral, z.onCoral),
    };
    return ChunkyBox(
      fill: fill,
      depth: 0,
      radius: 999,
      borderWidth: ZGame.outlineInner,
      highlight: false,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // A Row, not `alignment:` — an aligned box would stretch to the card.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              height: 1,
              color: on,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisabledPrimary extends StatelessWidget {
  final String label;

  const _DisabledPrimary({required this.label});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      button: true,
      enabled: false,
      label: label,
      child: Padding(
        // The live button reserves its solid edge; keep the layout still.
        padding: const EdgeInsets.only(bottom: ZGame.depthMd),
        child: ChunkyBox(
          fill: z.wash,
          depth: 0,
          radius: ZGame.dialogPrimaryRadius,
          height: ZGame.dialogPrimaryHeight,
          highlight: false,
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: Text(
              label,
              style: ZTypography.button.copyWith(
                fontSize: 19,
                height: 1,
                color: z.ink60,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A coin-reward chip of the invite dialog: tinted dot, bold amount, caption.
class ZRewardChip extends StatelessWidget {
  final String amount;
  final String caption;
  final Color dot;

  const ZRewardChip({
    super.key,
    required this.amount,
    required this.caption,
    required this.dot,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      depth: 0,
      radius: 14,
      borderWidth: ZGame.outlineInner,
      highlight: false,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          ChunkyBox(
            fill: dot,
            depth: 0,
            circle: true,
            borderWidth: ZGame.outlineInner,
            width: 26,
            height: 26,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amount,
                  maxLines: 1,
                  style: ZTypography.cardTitle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    color: z.ink,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
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
        ],
      ),
    );
  }
}

/// The dialog's text-field frame: 3px outline that turns coral on an error
/// and teal when accepted (canvas `borderFor`).
class ZDialogField extends StatelessWidget {
  final Color? border;
  final Widget child;

  const ZDialogField({super.key, this.border, required this.child});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      height: 54,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: z.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: border ?? context.zs.outline,
          width: ZGame.outline,
        ),
      ),
      child: child,
    );
  }
}
