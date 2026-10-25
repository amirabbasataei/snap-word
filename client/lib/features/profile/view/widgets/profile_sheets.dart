import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/perks_catalog_service.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/avatar_tile.dart';
import 'package:wordchain/core/widgets/z_coin.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';

/// The profile's two bottom sheets. The canvas draws neither, so they keep
/// the Material sheet frame (a shared `ZTray` is still to be built — todo.md
/// §3); moved here from the screen file, content unchanged apart from the
/// avatar picker's loading state, which is now `ZLoadState`.

Future<void> showAvatarPicker(
  BuildContext context, {
  required String? selected,
  required ValueChanged<String> onPick,
}) {
  final z = context.z;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: z.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ZRadius.sheetMax),
      ),
    ),
    builder:
        (sheetContext) => AvatarPickerSheet(
          selected: selected,
          onPick: (id) {
            Navigator.of(sheetContext).pop();
            onPick(id);
          },
        ),
  );
}

Future<void> showBuyCoinsSheet(
  BuildContext context, {
  required void Function(String productId) onPurchase,
}) {
  final z = context.z;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: z.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ZRadius.sheetMax),
      ),
    ),
    builder: (_) => BuyCoinsSheet(onPurchase: onPurchase),
  );
}

class AvatarPickerSheet extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onPick;

  const AvatarPickerSheet({
    super.key,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final catalog = getIt<PerksCatalogService>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ZSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'انتخاب آواتار',
                style: ZTypography.cardTitle.copyWith(color: z.ink),
              ),
            ),
            const SizedBox(height: ZSpacing.md),
            // Last known list shows at once; the fetch swaps in new entries.
            FutureBuilder<PerksCatalog>(
              initialData: catalog.cached,
              future: catalog.refresh(),
              builder: (context, snapshot) {
                final ids = snapshot.data?.avatarIds ?? const [];
                if (ids.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: ZSpacing.md),
                    child: Center(
                      child:
                          snapshot.connectionState == ConnectionState.done
                              ? Text(
                                'آواتاری در دسترس نیست',
                                style: ZTypography.metaLabel.copyWith(
                                  color: z.ink40,
                                ),
                              )
                              : const ZLoadState.loading(),
                    ),
                  );
                }
                return Wrap(
                  spacing: ZSpacing.md,
                  runSpacing: ZSpacing.md,
                  children: [
                    for (final id in ids)
                      GestureDetector(
                        onTap: () => onPick(id),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color:
                                  id == selected ? z.ink : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: AvatarTile(name: id, size: 56, avatarId: id),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BuyCoinsSheet extends StatelessWidget {
  final void Function(String productId) onPurchase;

  const BuyCoinsSheet({super.key, required this.onPurchase});

  static const bundles = [
    ('coins_100', '۱۰۰ سکه', '۹٬۰۰۰ تومان'),
    ('coins_350', '۳۵۰ سکه', '۲۵٬۰۰۰ تومان'),
    ('coins_1500', '۱۵۰۰ سکه', '۷۹٬۰۰۰ تومان'),
  ];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter,
          ZSpacing.xl,
          ZSpacing.screenGutter,
          ZSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'خرید سکه',
                style: ZTypography.metaLabel.copyWith(
                  color: z.ink40,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            for (final (id, title, price) in bundles)
              Padding(
                padding: const EdgeInsets.only(bottom: ZSpacing.md),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onPurchase(id);
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: z.wash,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const ZCoin(size: 24),
                        const SizedBox(width: ZSpacing.md),
                        Text(
                          title,
                          style: ZTypography.cardTitle.copyWith(
                            color: z.ink,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          price,
                          style: ZTypography.cardTitle.copyWith(
                            color: z.amberDeep,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
