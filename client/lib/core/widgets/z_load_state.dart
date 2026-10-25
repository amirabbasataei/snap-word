import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

/// The one loading / failed-load block of a screen's body. Both variants are
/// a mascot-led [ZEmptyState]-style stack, so every screen that adopts it
/// looks the same while it waits or when its first load fails.
///
/// It paints no background (see [ZEmptyState]). [ZLoadState.error] takes the
/// already-Persian [message] from the repository exception and offers
/// «تلاش دوباره»; screens keep already-loaded data on a *refresh* failure and
/// only show this when there is nothing to show.
class ZLoadState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const ZLoadState.loading({super.key}) : message = null, onRetry = null;

  const ZLoadState.error({
    super.key,
    required String this.message,
    required VoidCallback this.onRetry,
  });

  bool get _failed => message != null;

  static const loadingLabel = 'کمی صبر کن…';
  static const retryLabel = 'تلاش دوباره';

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return ZEmptyState(
        mood: ZMascotMood.sad,
        title: message!,
        actionLabel: retryLabel,
        onAction: onRetry,
        primaryAction: false,
      );
    }
    return Semantics(
      liveRegion: true,
      label: loadingLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZMascot(mood: ZMascotMood.thinking, size: 96),
          const SizedBox(height: 10),
          Text(
            loadingLabel,
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: context.z.ink60,
            ),
          ),
        ],
      ),
    );
  }
}
