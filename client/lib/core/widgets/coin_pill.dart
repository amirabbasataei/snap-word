import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

/// Coin balance pill — amber dot + Persian-formatted number
/// (e.g. `۱٬۲۴۰`), on a `surface` chip with a `line` border.
class CoinPill extends StatelessWidget {
  final int amount;

  const CoinPill({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: z.surface,
        borderRadius: BorderRadius.circular(ZRadius.chip),
        border: Border.all(color: z.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: z.amber, shape: BoxShape.circle),
          ),
          const SizedBox(width: ZSpacing.sm),
          Text(
            formatPersianNumber(amount),
            style: ZTypography.metaLabel.copyWith(
              color: z.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
