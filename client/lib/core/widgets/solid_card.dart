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

  const SolidCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ZSpacing.xl),
    this.radius = ZRadius.cardMin,
    this.color,
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
        boxShadow: ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth),
      ),
      child: child,
    );
  }
}
