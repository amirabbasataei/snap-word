import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/perks_catalog_service.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_game_bubbles.dart';

/// The premium taunts of a 1v1 match (canvas `ZVersusA`): the chunky button
/// beside the input card, the tray it opens, and the transient bubble the
/// latest taunt shows in.

/// Sub-line of the tray. The canvas says «یک طعنه در هر دست», which assumes
/// rounds; the real rule is the server's cooldown + per-match cap.
String zTauntRuleLine() => tauntRuleText();

const _freeLine =
    'ارسال فقط برای اشتراک ویژه فعال است؛ دریافت طعنه‌ها برای همه رایگان است.';

/// 66dp chunky button next to the input card. A crown badge marks it as a
/// premium feature; free players see a lock instead and the tray explains.
class ZTauntButton extends StatelessWidget {
  final bool premium;

  const ZTauntButton({super.key, required this.premium});

  static const _glyph =
      '<svg viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2.6" '
      'stroke-linejoin="round"><path d="M4 5h16v11H10l-5 4v-4H4z"/>'
      '<path d="M9 10.5h.01M12 10.5h.01M15 10.5h.01" stroke-linecap="round" '
      'stroke-width="3.2"/></svg>';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final ink = svgHex(premium ? z.ink : z.ink60);
    return ChunkyPressable(
      depth: ZGame.depthSm + 1,
      onTap: () => showZTauntTray(context, premium: premium),
      semanticLabel: premium ? 'طعنه' : 'طعنه، مخصوص اشتراک ویژه',
      builder:
          (context, depth, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              ChunkyBox(
                fill: premium ? z.surface : z.wash,
                depth: depth,
                radius: ZGame.gameInputRadius,
                highlight: false,
                width: ZGame.gameInputHeight,
                height: ZGame.gameInputHeight,
                alignment: Alignment.center,
                child: SvgPicture.string(
                  _glyph.replaceFirst('%s', ink),
                  width: 24,
                  height: 24,
                ),
              ),
              PositionedDirectional(
                top: -11,
                end: -7,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: premium ? z.amber : z.inkSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: zs.outline,
                      width: ZGame.outlineInner,
                    ),
                  ),
                  child: Icon(
                    premium
                        ? Icons.workspace_premium_rounded
                        : Icons.lock_rounded,
                    size: 14,
                    color: premium ? z.onAmber : z.onInkSurface,
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

/// Opens the tray over the game. Picking a taunt sends [TauntSent] and closes.
Future<void> showZTauntTray(BuildContext context, {required bool premium}) {
  final bloc = context.read<GameBloc>();
  return showZDialog<void>(
    context,
    builder:
        (dialogContext) => ZTauntTray(
          premium: premium,
          catalog: getIt<PerksCatalogService>(),
          onSend: (id) {
            bloc.add(TauntSent(id));
            Navigator.of(dialogContext).pop();
          },
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
  );
}

/// The tray: header (crown tag, title, rule line, close), the taunts in two
/// columns (a skeleton while the first fetch runs; the last known list shows
/// at once), muted and locked for free players.
class ZTauntTray extends StatefulWidget {
  final bool premium;
  final PerksCatalogService catalog;
  final void Function(String id) onSend;
  final VoidCallback onClose;

  const ZTauntTray({
    super.key,
    required this.premium,
    required this.catalog,
    required this.onSend,
    required this.onClose,
  });

  @override
  State<ZTauntTray> createState() => _ZTauntTrayState();
}

class _ZTauntTrayState extends State<ZTauntTray> {
  late final Future<PerksCatalog> _fetch = widget.catalog.refresh();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZDialogCard(
      semanticLabel: 'طعنه بفرست',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrayHeader(premium: widget.premium, onClose: widget.onClose),
          const SizedBox(height: 12),
          FutureBuilder<PerksCatalog>(
            initialData: widget.catalog.cached,
            future: _fetch,
            builder: (context, snapshot) {
              final taunts = snapshot.data?.taunts ?? const <PerkTaunt>[];
              final done = snapshot.connectionState == ConnectionState.done;
              if (taunts.isEmpty) {
                return done
                    ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'طعنه‌ای در دسترس نیست',
                          style: TextStyle(
                            color: z.ink60,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                    : _Grid(
                      children: [for (var i = 0; i < 6; i++) const _Skeleton()],
                    );
              }
              return _Grid(
                children: [
                  for (final t in taunts)
                    _TauntChip(
                      text: t.text,
                      locked: !widget.premium,
                      onTap: () => widget.onSend(t.id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TrayHeader extends StatelessWidget {
  final bool premium;
  final VoidCallback onClose;

  const _TrayHeader({required this.premium, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final ink = svgHex(z.ink);
    return Row(
      children: [
        ZChunkPill(
          fill: z.amber,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded, size: 13, color: z.onAmber),
              const SizedBox(width: 5),
              Text(
                'ویژه',
                style: TextStyle(
                  color: z.onAmber,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'طعنه بفرست',
                style: TextStyle(
                  color: z.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  height: 1.2,
                ),
              ),
              Text(
                premium ? zTauntRuleLine() : _freeLine,
                style: TextStyle(
                  color: z.ink60,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ChunkyPressable(
          depth: ZGame.depthSm - 1,
          onTap: onClose,
          semanticLabel: 'بستن',
          builder:
              (context, depth, _) => ChunkyBox(
                fill: z.wash,
                depth: depth,
                radius: 13,
                highlight: false,
                borderWidth: ZGame.outlineInner,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: SvgPicture.string(
                  '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="3" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
                  width: 16,
                  height: 16,
                ),
              ),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  final List<Widget> children;

  const _Grid({required this.children});

  @override
  Widget build(BuildContext context) {
    // Two columns; a row is as tall as its taller chip, so a long taunt that
    // wraps (large text scale) never clips.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      i + 1 < children.length
                          ? children[i + 1]
                          : const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    decoration: BoxDecoration(
      color: context.z.wash,
      borderRadius: BorderRadius.circular(15),
    ),
  );
}

class _TauntChip extends StatelessWidget {
  final String text;
  final bool locked;
  final VoidCallback onTap;

  const _TauntChip({
    required this.text,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final label = Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: locked ? z.ink60 : z.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
        ),
        if (locked) Icon(Icons.lock_outline_rounded, size: 14, color: z.ink60),
      ],
    );
    if (locked) {
      return Semantics(
        label: '$text، مخصوص اشتراک ویژه',
        excludeSemantics: true,
        child: ChunkyBox(
          fill: z.wash,
          depth: 0,
          radius: 15,
          highlight: false,
          borderWidth: ZGame.outlineInner,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: AlignmentDirectional.centerStart,
          child: label,
        ),
      );
    }
    return ChunkyPressable(
      depth: ZGame.depthSm,
      onTap: onTap,
      semanticLabel: text,
      builder:
          (context, depth, _) => ChunkyBox(
            fill: z.paper,
            depth: depth,
            radius: 15,
            highlight: false,
            borderWidth: ZGame.outlineInner,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            alignment: AlignmentDirectional.centerStart,
            child: label,
          ),
    );
  }
}

/// The shared chain of a 1v1 match with the latest taunt inline (canvas
/// `ZVersusA`): an amber pill with the sender's disc, right under the sender's
/// last word, shown for [visibleFor] on both devices alike. The game state only
/// keeps the latest taunt, so unlike the canvas an older one is not part of the
/// chain history. This widget owns the timer; [ZBubbleChain] only draws.
class ZVersusChain extends StatefulWidget {
  final GameActive state;
  final String myInitial;
  final Widget Function(double size)? myAvatar;
  final Widget Function(double size)? opponentAvatar;

  const ZVersusChain({
    super.key,
    required this.state,
    required this.myInitial,
    this.myAvatar,
    this.opponentAvatar,
  });

  static const visibleFor = Duration(seconds: 3);

  @override
  State<ZVersusChain> createState() => ZVersusChainState();
}

@visibleForTesting
class ZVersusChainState extends State<ZVersusChain> {
  Timer? _hideTimer;
  int _shownSeq = 0;
  bool _visible = false;

  @override
  void didUpdateWidget(ZVersusChain oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seq = widget.state.tauntSeq;
    if (seq != oldWidget.state.tauntSeq && seq != _shownSeq) {
      _shownSeq = seq;
      _visible = true;
      _hideTimer?.cancel();
      _hideTimer = Timer(ZVersusChain.visibleFor, () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final entries = zBubbleEntries(
      state,
      isMine:
          (i) =>
              i < state.wordOwners.length &&
              state.wordOwners[i] == state.myPlayerId,
    );
    final text = state.tauntText;
    return ZBubbleChain(
      entries: entries,
      nextStartLetter: state.nextStartLetter,
      myTurn: state.isMyTurn,
      myInitial: widget.myInitial,
      myAvatar: widget.myAvatar,
      opponentAvatar: widget.opponentAvatar,
      taunt:
          text == null
              ? null
              : ZChainTaunt(
                text: text,
                mine: state.tauntFromMe,
                afterIndex: zTauntAnchor(entries, mine: state.tauntFromMe),
                visible: _visible,
              ),
    );
  }
}

TextDirection flipDirection(TextDirection d) =>
    d == TextDirection.rtl ? TextDirection.ltr : TextDirection.rtl;
