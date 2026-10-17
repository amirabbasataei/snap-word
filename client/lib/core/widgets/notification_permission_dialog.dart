import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

const _askedKey = 'notification_permission_asked';

/// Explains why notifications matter and, only if the player agrees, triggers
/// the OS permission prompt. Shown at most once (when the Friends tab is first
/// opened) and never when the permission is already granted.
Future<void> maybeAskNotificationPermission(BuildContext context) async {
  final prefs = getIt<SharedPreferences>();
  if (prefs.getBool(_askedKey) ?? false) return;
  final notifications = getIt<NotificationService>();
  if (await notifications.isAuthorized()) return;
  await prefs.setBool(_askedKey, true);
  if (!context.mounted) return;
  final agreed = await showZDialog<bool>(
    context,
    builder: (dialogContext) => _NotificationPermissionDialog(
      onAgree: () => Navigator.of(dialogContext).pop(true),
      onLater: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  if (agreed == true) {
    await notifications.requestPermission();
    await notifications.registerToken();
  }
}

class _NotificationPermissionDialog extends StatelessWidget {
  final VoidCallback onAgree;
  final VoidCallback onLater;

  const _NotificationPermissionDialog({
    required this.onAgree,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZDialogCard(
      semanticLabel: 'از دوستانت جا نمون!',
      mascot: const ZMascot(
        mood: ZMascotMood.happy,
        size: ZGame.dialogMascotSize,
        shadow: false,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'از دوستانت جا نمون!',
            textAlign: TextAlign.center,
            style: ZTypography.screenTitle.copyWith(
              color: z.ink,
              fontSize: 22,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'با فعال‌کردن اعلان‌ها بلافاصله می‌فهمی کسی درخواست دوستی داده، '
            'تو را به چالش دعوت کرده یا جایزه‌ات آماده است.',
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.65,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 18),
          ZDialogButton.primary(label: 'فعال‌سازی اعلان‌ها', onTap: onAgree),
          const SizedBox(height: 7),
          ZDialogButton.secondary(label: 'بعداً', onTap: onLater),
        ],
      ),
    );
  }
}
