import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_motion.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

enum ZToastKind { info, success, error }

/// App-wide transient notice, pinned to the top of the screen. Replaces
/// `SnackBar` everywhere; only one toast is visible at a time.
abstract final class ZToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(BuildContext context, String message, {ZToastKind kind = ZToastKind.info}) {
    showOn(Overlay.of(context, rootOverlay: true), message, kind: kind);
  }

  /// For call sites that outlive their widget across an `await`: capture
  /// `Overlay.of(context, rootOverlay: true)` first, then call this.
  static void showOn(OverlayState overlay, String message, {ZToastKind kind = ZToastKind.info}) {
    _dismiss();
    final entry = OverlayEntry(
      builder: (_) => _ToastView(message: message, kind: kind, onDismissed: () {
        if (_entry == null) return;
        _dismiss();
      }),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    final e = _entry;
    _entry = null;
    if (e != null && e.mounted) e.remove();
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final ZToastKind kind;
  final VoidCallback onDismissed;

  const _ToastView({required this.message, required this.kind, required this.onDismissed});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: ZMotion.tileDrop,
    reverseDuration: ZMotion.bubbleEnter,
  )..forward();
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _hideTimer = Timer(const Duration(milliseconds: 2600), _hide);
  }

  Future<void> _hide() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (accent, deep, onAccent, icon) = switch (widget.kind) {
      ZToastKind.success => (z.teal, z.tealDeep, z.onTeal, Icons.check_rounded),
      ZToastKind.error => (z.coral, z.coralDeep, z.onCoral, Icons.priority_high_rounded),
      ZToastKind.info => (z.indigo, z.indigoDeep, z.onIndigo, Icons.bolt_rounded),
    };
    final top = MediaQuery.of(context).padding.top + ZSpacing.md;

    return Positioned(
      top: top,
      left: ZSpacing.lg,
      right: ZSpacing.lg,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_ctrl.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, (1 - t) * -24), child: child),
            );
          },
          child: GestureDetector(
            onTap: _hide,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) _hide();
            },
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    ZSpacing.md, ZSpacing.md, ZSpacing.lg, ZSpacing.md),
                decoration: BoxDecoration(
                  color: z.surface,
                  borderRadius: BorderRadius.circular(ZRadius.cardMin),
                  border: Border.all(color: z.line, width: 1),
                  boxShadow: ZElevation.solidEdge(deep, depth: ZElevation.cardDepth),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: ZElevation.solidEdge(deep, depth: 2),
                      ),
                      child: Icon(icon, size: 20, color: onAccent),
                    ),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: ZTypography.body.copyWith(color: z.ink, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
