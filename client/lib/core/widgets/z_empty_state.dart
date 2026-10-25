import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

/// The mascot-led "nothing here" block: a standing [ZMascot], a title, an
/// optional body line and an optional action. Used for empty lists, guest
/// gates and (through `ZLoadState.error`) failed loads.
///
/// It paints no background: put it inside a card, or directly on a surface the
/// caller has checked for contrast. The action button is a fixed-height chunky
/// control, so the label ignores text scale above 1.3×; title and body scale
/// freely and wrap.
class ZEmptyState extends StatelessWidget {
  final String title;
  final String? body;
  final ZMascotMood mood;

  /// Width of the mascot (its box keeps the canvas ratio).
  final double mascotSize;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The action is the filled [actionAccent] button; with false it is the
  /// neutral surface button (retry, secondary choices).
  final bool primaryAction;
  final ZDialogAccent actionAccent;

  const ZEmptyState({
    super.key,
    required this.title,
    this.body,
    this.mood = ZMascotMood.idle,
    this.mascotSize = 96,
    this.actionLabel,
    this.onAction,
    this.primaryAction = true,
    this.actionAccent = ZDialogAccent.teal,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'actionLabel and onAction go together',
       );

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final label = actionLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ExcludeSemantics(child: ZMascot(mood: mood, size: mascotSize)),
        ),
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: ZTypography.screenTitle.copyWith(
              fontSize: 18,
              height: 1.4,
              color: z.ink,
            ),
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.65,
              color: z.ink60,
            ),
          ),
        ],
        if (label != null) ...[
          const SizedBox(height: 16),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child:
                primaryAction
                    ? ZDialogButton.primary(
                      label: label,
                      onTap: onAction,
                      accent: actionAccent,
                      height: 52,
                      radius: 18,
                      depth: 4,
                      fontSize: 16,
                    )
                    : ZDialogButton.secondary(
                      label: label,
                      onTap: onAction,
                      height: 50,
                      radius: 16,
                      depth: 4,
                    ),
          ),
        ],
      ],
    );
  }
}
