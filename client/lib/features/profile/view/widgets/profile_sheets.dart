import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/perks_catalog_service.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/avatar_tile.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';

/// The profile's avatar picker sheet. The canvas does not draw it, so it keeps
/// the Material sheet frame (a shared `ZTray` is still to be built — todo.md
/// §3). The coin shop is `buy_coins_dialog.dart`.

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
