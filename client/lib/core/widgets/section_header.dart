import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

/// Section title row with an optional trailing action ("see all", a count).
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: ZTypography.cardTitle.copyWith(color: z.ink),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
