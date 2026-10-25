import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// The full-width surface card that holds a screen's no-list states — loading,
/// failed load, guest gate, empty list — on top of the sky scene. Put a
/// `ZLoadState` or `ZEmptyState` inside.
class ZStateCard extends StatelessWidget {
  final Widget child;

  const ZStateCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ChunkyBox(
      fill: context.z.surface,
      depth: ZGame.depthMd,
      radius: 22,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      width: double.infinity,
      child: child,
    );
  }
}
