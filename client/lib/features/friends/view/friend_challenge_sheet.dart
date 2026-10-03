import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// Confirmation sheet for a friend challenge (Classic is the only mode). No canvas design — derived from the
/// token system (REDESIGN_PLAN.md Stage 6).
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
              Text(
                'کلاسیک · هر نوبت ${toPersianDigits(GameConstants.classicTurnTimerSec)} ثانیه · اولین اشتباه می‌بازد',
                style: ZTypography.body.copyWith(color: z.ink60),
              ),
              const SizedBox(height: ZSpacing.xxl),
              AccentButton(
                accent: ZAccentColor.indigo,
                label: 'ارسال چالش',
                onPressed: () {
                  context.pop();
                  widget.onSend('classic');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
