import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_theme.dart';

class TimerBar extends StatelessWidget {
  final int timeRemaining;
  final int totalTime;

  const TimerBar({
    super.key,
    required this.timeRemaining,
    required this.totalTime,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = totalTime > 0 ? (timeRemaining / totalTime).clamp(0.0, 1.0) : 0.0;
    final isUrgent = fraction <= 0.33;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'TURN TIMER',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${timeRemaining}s',
                style: TextStyle(
                  color: isUrgent ? AppColors.error : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: fraction, end: fraction),
              duration: const Duration(milliseconds: 400),
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isUrgent ? AppColors.error : AppColors.secondary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
