import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_accent_disc.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/messages/view/widgets/message_format.dart';

/// One invitation card (canvas `ZNotifs`): the coloured disc with the sender's
/// initial, the title and text, then the teal accept button and the neutral
/// decline button side by side, inset to line up under the text.
///
/// The canvas's unread dot, time stamp, «بعداً» and «done» line are not drawn:
/// the server keeps no read state or creation time for these, the decline is
/// final (not "later"), and an answered invitation leaves the list at once.
class MessageTile extends StatelessWidget {
  final MessageFace face;

  /// An answer for this invitation is in flight: the accept button reads
  /// «کمی صبر کن…» and both ignore taps.
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const MessageTile({
    super.key,
    required this.face,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  /// Disc width + the gap after it: the buttons start under the text.
  static const _textInset = 64.0;

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
              ZAccentDisc(glyph: face.glyph, accent: face.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      face.title,
                      style: ZTypography.cardTitle.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        height: 1.35,
                        color: z.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      face.body,
                      style: ZTypography.body.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.55,
                        color: z.ink60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: _textInset),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: face.acceptSemantics,
                      button: true,
                      excludeSemantics: true,
                      onTap: busy ? null : onAccept,
                      child: ZDialogButton.primary(
                        label: busy ? 'کمی صبر کن…' : face.acceptLabel,
                        onTap: busy ? null : onAccept,
                        height: 44,
                        radius: 14,
                        depth: 4,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      label: face.declineSemantics,
                      button: true,
                      excludeSemantics: true,
                      onTap: busy ? null : onDecline,
                      child: ZDialogButton.secondary(
                        label: face.declineLabel,
                        onTap: busy ? null : onDecline,
                        height: 44,
                        radius: 14,
                        depth: 4,
                        fontSize: 14,
                      ),
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
