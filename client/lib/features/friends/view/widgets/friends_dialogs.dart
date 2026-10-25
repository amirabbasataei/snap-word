import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/friends/view/widgets/friends_parts.dart';

/// Asks for the exact username of a friend to send a request to. Resolves to
/// the trimmed username, or null when the player cancels. Replaces the
/// Material bottom sheet; the field stays above the soft keyboard (see
/// `showZDialog`).
Future<String?> showAddFriendDialog(BuildContext context) =>
    showZDialog<String>(context, builder: (_) => const AddFriendDialog());

class AddFriendDialog extends StatefulWidget {
  const AddFriendDialog({super.key});

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _controller.text.trim();
    if (username.isEmpty) return;
    Navigator.of(context).pop(username);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final fieldStyle = ZTypography.cardTitle.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: z.ink,
    );
    return ZDialogCard(
      semanticLabel: 'افزودن دوست',
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'افزودن دوست',
            textAlign: TextAlign.center,
            style: ZTypography.screenTitle.copyWith(
              fontSize: 21,
              height: 1.35,
              color: z.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'نام کاربری دقیق دوستت را بنویس تا برایش درخواست دوستی بفرستیم.',
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.65,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 14),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: ChunkyBox(
              fill: z.wash,
              depth: 0,
              radius: 16,
              highlight: false,
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: AlignmentDirectional.centerStart,
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                cursorColor: z.indigo,
                style: fieldStyle,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'نام کاربری',
                  hintStyle: fieldStyle.copyWith(color: z.ink60),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 10,
                  child: ZDialogButton.secondary(
                    label: 'بی‌خیال',
                    onTap: () => Navigator.of(context).pop(),
                    height: 54,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 16,
                  child: ZDialogButton.primary(
                    label: 'ارسال درخواست',
                    onTap: _submit,
                    height: 54,
                    radius: 18,
                    depth: ZGame.depthSm + 1,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before removing a friend (long press on a row). Resolves to true only
/// for «حذف»; «بی‌خیال», the scrim and back all give false.
Future<bool> showRemoveFriendDialog(
  BuildContext context, {
  required String friendUsername,
}) async {
  final remove = await showZDialog<bool>(
    context,
    builder:
        (dialogContext) => RemoveFriendDialog(
          friendUsername: friendUsername,
          onConfirm: () => Navigator.of(dialogContext).pop(true),
          onCancel: () => Navigator.of(dialogContext).pop(false),
        ),
  );
  return remove ?? false;
}

class RemoveFriendDialog extends StatelessWidget {
  final String friendUsername;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const RemoveFriendDialog({
    super.key,
    required this.friendUsername,
    required this.onConfirm,
    required this.onCancel,
  });

  static String titleFor(String friendUsername) =>
      '${isolate(friendUsername)} را از دوستان حذف کنی؟';

  static const body =
      'دیگر در فهرست دوستانت نیست و نمی‌توانی برایش چالش بفرستی. '
      'اگر پشیمان شدی باید دوباره درخواست دوستی بدهی.';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final title = titleFor(friendUsername);
    return ZDialogCard(
      semanticLabel: title,
      mascot: const ZMascot(
        mood: ZMascotMood.sad,
        size: ZGame.dialogMascotSize,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: ZTypography.screenTitle.copyWith(
              fontSize: 21,
              height: 1.35,
              color: z.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.65,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 16),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 10,
                  child: ZDialogButton.secondary(
                    label: 'بی‌خیال',
                    onTap: onCancel,
                    height: 54,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 10,
                  child: ZDialogButton.primary(
                    label: 'حذف',
                    onTap: onConfirm,
                    accent: ZDialogAccent.coral,
                    height: 54,
                    radius: 18,
                    depth: ZGame.depthSm + 1,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
