import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/features/home/view/widgets/home_motion.dart';

/// Bottom-anchored, scrollable body of a game chain (ZSolo's spine, ZPlay's
/// bubbles): the newest item sits just above the input, older ones stay
/// reachable by scrolling up and fade under the HUD, and a new item (a change
/// of [itemCount]) scrolls back down.
///
/// [overlay] is pinned over the top of the viewport and told whether the list
/// is at its newest item; it is skipped when the viewport is shorter than
/// [overlayMinHeight] (the keyboard is up).
class ZChainScroller extends StatefulWidget {
  final int itemCount;
  final Widget child;
  final EdgeInsets padding;
  final Widget Function(BuildContext context, bool atBottom)? overlay;
  final double overlayMinHeight;

  const ZChainScroller({
    super.key,
    required this.itemCount,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 14),
    this.overlay,
    this.overlayMinHeight = 300,
  });

  @override
  State<ZChainScroller> createState() => _ZChainScrollerState();
}

class _ZChainScrollerState extends State<ZChainScroller> {
  final _controller = ScrollController();

  /// Scrolled to the newest item (offset 0 — the list is reversed).
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final at = !_controller.hasClients || _controller.offset < 24;
      if (at != _atBottom) setState(() => _atBottom = at);
    });
  }

  @override
  void didUpdateWidget(ZChainScroller old) {
    super.didUpdateWidget(old);
    if (widget.itemCount != old.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        if (homeReducedMotion(context)) {
          _controller.jumpTo(0);
        } else {
          _controller.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    return LayoutBuilder(
      builder: (context, c) {
        final scroll = SingleChildScrollView(
          controller: _controller,
          reverse: true,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: c.maxHeight - padding.vertical,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: widget.child,
            ),
          ),
        );
        // Items scrolling out under the HUD fade instead of being cut off.
        final mask = context.z.ink;
        final faded = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback:
              (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // dstIn mask: only the alpha channel matters.
                colors: [mask.withValues(alpha: 0), mask],
                stops: [0, (28 / rect.height).clamp(0.0, 1.0)],
              ).createShader(rect),
          child: scroll,
        );
        final overlay = widget.overlay;
        if (overlay == null || c.maxHeight < widget.overlayMinHeight) {
          return faded;
        }
        return Stack(
          children: [
            Positioned.fill(child: faded),
            PositionedDirectional(
              top: 8,
              start: 0,
              end: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _atBottom ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Center(child: overlay(context, _atBottom)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
