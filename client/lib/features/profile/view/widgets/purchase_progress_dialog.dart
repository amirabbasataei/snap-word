import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// Blocks the screen while a store purchase is in flight: connecting to the
/// Cafe Bazaar app can take several seconds and, without this, the buy button
/// looks dead and can be tapped twice. Not dismissible; the caller closes it
/// with the returned function once the purchase finished (any outcome).
VoidCallback showPurchaseProgress(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showZDialog<void>(
    context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: _PurchaseProgress()),
  ).whenComplete(() => open = false);
  return () {
    if (open && navigator.mounted) {
      open = false;
      navigator.pop();
    }
  };
}

class _PurchaseProgress extends StatelessWidget {
  const _PurchaseProgress();

  static const label = 'در حال اتصال به کافه‌بازار…';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZDialogCard(
      semanticLabel: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3, color: z.ink),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              label,
              style: ZTypography.body.copyWith(
                fontWeight: FontWeight.w800,
                color: z.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
