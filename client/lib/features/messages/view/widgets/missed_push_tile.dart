import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_accent_disc.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';

/// A push that arrived during a game (held back so no banner covers the
/// board): the title and text it carried, and one button to clear it.
class MissedPushTile extends StatelessWidget {
  final MissedPush push;
  final VoidCallback onDismiss;

  const MissedPushTile({
    super.key,
    required this.push,
    required this.onDismiss,
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
              const ZAccentDisc(glyph: '!', accent: ZDialogAccent.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (push.title.isNotEmpty)
                      Text(
                        push.title,
                        style: ZTypography.cardTitle.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                          color: z.ink,
                        ),
                      ),
                    if (push.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        push.body,
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
              child: ZDialogButton.secondary(
                label: 'باشه',
                onTap: onDismiss,
                height: 44,
                radius: 14,
                depth: 4,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
