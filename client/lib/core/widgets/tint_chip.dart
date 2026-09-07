import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

enum ZTint { indigo, teal, coral }

/// Soft pill chip on a tint background with matching accent text — status
/// labels, badges, small annotations.
class TintChip extends StatelessWidget {
  final String label;
  final ZTint tint;

  const TintChip({super.key, required this.label, this.tint = ZTint.indigo});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (bg, fg) = switch (tint) {
      ZTint.indigo => (z.tintIndigo, z.indigo),
      ZTint.teal => (z.tintTeal, z.teal),
      ZTint.coral => (z.tintCoral, z.coral),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ZRadius.chip),
      ),
      child: Text(
        label,
        style: ZTypography.metaLabel.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
