import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/core/widgets/z_icon.dart';

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
  final agreed = await showDialog<bool>(
    context: context,
    builder: (_) => const _NotificationPermissionDialog(),
  );
  if (agreed == true) {
    await notifications.requestPermission();
    await notifications.registerToken();
  }
}

class _NotificationPermissionDialog extends StatelessWidget {
  const _NotificationPermissionDialog();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Dialog(
      backgroundColor: z.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: ZSpacing.screenGutter,
        vertical: ZSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZRadius.cardMax),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: z.indigo.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: ZIcon('bell-ring', size: 32, color: z.indigo),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            Text(
              'از دوستانت جا نمون!',
              textAlign: TextAlign.center,
              style: ZTypography.screenTitle.copyWith(
                color: z.ink,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              'با فعال‌کردن اعلان‌ها بلافاصله می‌فهمی کسی درخواست دوستی داده، '
              'تو را به چالش دعوت کرده یا جایزه‌ات آماده است.',
              textAlign: TextAlign.center,
              style: ZTypography.body.copyWith(color: z.ink60),
            ),
            const SizedBox(height: ZSpacing.xl),
            AccentButton(
              label: 'فعال‌سازی اعلان‌ها',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: ZSpacing.sm),
            NeutralButton(
              label: 'بعداً',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
