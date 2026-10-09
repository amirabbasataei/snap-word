import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/premium_catalog.dart';

/// Rounded-square initial avatar (32–64px). The accent is derived from the
/// name so the same person always gets the same tile colour. A known premium
/// [avatarId] swaps the initial for that avatar's illustration.
class AvatarTile extends StatelessWidget {
  final String name;
  final double size;
  final String? avatarId;

  const AvatarTile({
    super.key,
    required this.name,
    this.size = 40,
    this.avatarId,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final accents = [
      (z.indigo, z.onIndigo, z.indigoDeep),
      (z.teal, z.onTeal, z.tealDeep),
      (z.amber, z.onAmber, z.amberDeep),
      (z.coral, z.onCoral, z.coralDeep),
    ];
    final trimmed = name.trim();
    final hasArt = PremiumCatalog.hasAvatar(avatarId);
    final index =
        hasArt
            ? PremiumCatalog.avatarIndex(avatarId!) % accents.length
            : trimmed.isEmpty
            ? 0
            : trimmed.codeUnitAt(0) % accents.length;
    final (bg, onColor, deep) = accents[index];
    final initial =
        trimmed.isEmpty ? '؟' : trimmed.substring(0, 1).toUpperCase();
    final radius = (size * (ZRadius.tileMax / ZTileSize.heroMax)).clamp(
      ZRadius.tileMin,
      ZRadius.tileMax,
    );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ZElevation.solidEdge(deep, depth: ZElevation.tileDepth),
      ),
      child:
          hasArt
              ? Image.asset(
                PremiumCatalog.avatarAsset(avatarId!),
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              )
              : Text(
                initial,
                style: ZTypography.cardTitle.copyWith(
                  color: onColor,
                  fontSize: size * 0.4,
                ),
              ),
    );
  }
}
