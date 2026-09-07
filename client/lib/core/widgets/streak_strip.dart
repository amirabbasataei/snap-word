import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';

/// A row of 7–8 day chips marking a streak — filled `teal` for completed
/// days, an outlined `wash` chip otherwise.
class StreakStrip extends StatelessWidget {
  final int totalDays;
  final int completedDays;

  const StreakStrip({
    super.key,
    this.totalDays = 7,
    required this.completedDays,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(totalDays, (i) {
        final done = i < completedDays;
        return Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? z.teal : z.wash,
            borderRadius: BorderRadius.circular(ZRadius.tileMin),
            border: done ? null : Border.all(color: z.line),
            boxShadow: done
                ? ZElevation.solidEdge(z.tealDeep, depth: ZElevation.tileDepth)
                : null,
          ),
          child: done
              ? Icon(Icons.check, size: 14, color: z.onTeal)
              : null,
        );
      }),
    );
  }
}
