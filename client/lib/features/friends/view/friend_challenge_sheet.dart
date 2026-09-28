import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// Mode picker for a friend challenge. No canvas design — derived from the
/// token system (REDESIGN_PLAN.md Stage 6), matching ZLobby's mode toggle.
class FriendChallengeSheet extends StatefulWidget {
  final String friendUsername;
  final void Function(String mode) onSend;

  const FriendChallengeSheet({
    super.key,
    required this.friendUsername,
    required this.onSend,
  });

  @override
  State<FriendChallengeSheet> createState() => _FriendChallengeSheetState();
}

class _FriendChallengeSheetState extends State<FriendChallengeSheet> {
  String _selectedMode = 'classic';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      decoration: BoxDecoration(
        color: z.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZRadius.sheetMin)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ZSpacing.xxl, ZSpacing.xl, ZSpacing.xxl, ZSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('چالش با دوست',
                            style: ZTypography.screenTitle.copyWith(color: z.ink)),
                        const SizedBox(height: 2),
                        Text(widget.friendUsername,
                            style: ZTypography.body.copyWith(color: z.ink60)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: z.ink40),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
              const SizedBox(height: ZSpacing.xl),
              Text('نوع بازی',
                  style: ZTypography.metaLabel.copyWith(color: z.ink40)),
              const SizedBox(height: ZSpacing.sm),
              _ModeOption(
                title: 'کلاسیک',
                subtitle:
                    'هر نوبت ${toPersianDigits(GameConstants.classicTurnTimerSec)} ثانیه · اولین اشتباه می‌بازد',
                selected: _selectedMode == 'classic',
                onTap: () => setState(() => _selectedMode = 'classic'),
              ),
              const SizedBox(height: ZSpacing.sm),
              _ModeOption(
                title: 'زمان‌دار',
                subtitle:
                    'هر نوبت ${toPersianDigits(GameConstants.timeAttackTurnTimerSec)} ثانیه · بازی ${toPersianDigits(GameConstants.timeAttackMatchDurationSec)} ثانیه · امتیاز بیشتر می‌برد',
                selected: _selectedMode == 'time_attack',
                onTap: () => setState(() => _selectedMode = 'time_attack'),
              ),
              const SizedBox(height: ZSpacing.xxl),
              AccentButton(
                accent: ZAccentColor.indigo,
                label: 'ارسال چالش',
                onPressed: () {
                  context.pop();
                  widget.onSend(_selectedMode);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(ZSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? z.tintIndigo : z.surface,
          borderRadius: BorderRadius.circular(ZRadius.tileMax),
          border: Border.all(
            color: selected ? z.indigo : z.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: ZTypography.cardTitle
                          .copyWith(color: selected ? z.indigo : z.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: ZTypography.metaLabel.copyWith(color: z.ink60)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: z.indigo, size: 20),
          ],
        ),
      ),
    );
  }
}
