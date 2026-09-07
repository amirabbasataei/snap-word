import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';

/// Standard card shell used across all 11 screens: `surface` fill, a 1px
/// `line` border, and a solid `0 3px 0 line` bottom edge — no blur shadow.
class SolidCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  /// Some cards in the design (e.g. ZHome's streak card) sit flush on
  /// `surface` with just a 1px `line` border and no offset edge — set to
  /// `false` to drop the `0 3px 0 line` shadow.
  final bool elevated;

  const SolidCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ZSpacing.xl),
    this.radius = ZRadius.cardMin,
    this.color,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? z.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: z.line, width: 1),
        boxShadow: elevated
            ? ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth)
            : null,
      ),
      child: child,
    );
  }
}
