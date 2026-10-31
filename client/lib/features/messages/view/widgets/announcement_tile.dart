import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_accent_disc.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/messages/data/inbox_repository.dart';

/// A notice an admin sent from the panel: title and text, a «باشه» that clears
/// it and — when the message points somewhere (`route`) — an «نمایش» that
/// opens that screen and clears it too.
class AnnouncementTile extends StatelessWidget {
  final InboxMessage message;
  final VoidCallback onDismiss;
  final VoidCallback? onOpen;

  const AnnouncementTile({
    super.key,
    required this.message,
    required this.onDismiss,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      depth: 4,
      radius: 18,
      highlight: false,
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ZAccentDisc(glyph: 'پ', accent: ZDialogAccent.teal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.title.isNotEmpty)
                      Text(
                        message.title,
                        style: ZTypography.cardTitle.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                          color: z.ink,
                        ),
                      ),
                    if (message.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        message.body,
                        style: ZTypography.body.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.55,
                          color: z.ink60,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 64),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Row(
                children: [
                  if (onOpen != null) ...[
                    Expanded(
                      child: ZDialogButton.primary(
                        label: 'نمایش',
                        onTap: onOpen,
                        height: 44,
                        radius: 14,
                        depth: 4,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ZDialogButton.secondary(
                      label: 'باشه',
                      onTap: onDismiss,
                      height: 44,
                      radius: 14,
                      depth: 4,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
