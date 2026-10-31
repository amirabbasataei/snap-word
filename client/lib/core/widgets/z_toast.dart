import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';

enum ZToastKind { info, success, error, coin }

/// App-wide transient notice (canvas `ZToast`, frames 16a/16b): a chunky card
/// that drops in from the top, drains a bar over its lifetime and goes away on
/// its own or on ✕. Only one toast is visible at a time.
abstract final class ZToast {
  /// Canvas default `duration`.
  static const defaultDuration = Duration(seconds: 4);

  static OverlayEntry? _entry;

  /// [title] is the one-liner; [message] adds the grey second line and
  /// [amount] the coin chip (both optional). [actionLabel] (screen-reader
  /// label) + [onAction] add a ✓ beside the ✕; tapping it runs [onAction] and
  /// dismisses the toast.
  static void show(
    BuildContext context,
    String title, {
    String? message,
    String? amount,
    ZToastKind kind = ZToastKind.info,
    Duration duration = defaultDuration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showOn(
      Overlay.of(context, rootOverlay: true),
      title,
      message: message,
      amount: amount,
      kind: kind,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// For call sites that outlive their widget across an `await`: capture
  /// `Overlay.of(context, rootOverlay: true)` first, then call this.
  static void showOn(
    OverlayState overlay,
    String title, {
    String? message,
    String? amount,
    ZToastKind kind = ZToastKind.info,
    Duration duration = defaultDuration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _dismiss();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (_) => Positioned.fill(
            child: ZToastCard.floating(
              title: title,
              message: message,
              amount: amount,
              kind: kind,
              duration: duration,
              actionLabel: actionLabel,
              onAction: onAction,
              onDismissed: () {
                if (_entry == entry) _dismiss();
              },
            ),
          ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void _dismiss() {
    final e = _entry;
    _entry = null;
    if (e != null && e.mounted) e.remove();
  }
}

/// Canvas `dropin` easing, `cubic-bezier(.34,1.56,.64,1)`.
const _spring = Cubic(.34, 1.56, .64, 1);

/// The toast itself. [ZToast] floats it over the screen; the goldens and any
/// in-flow use build it directly.
class ZToastCard extends StatefulWidget {
  final String title;
  final String? message;
  final String? amount;
  final ZToastKind kind;
  final Duration duration;
  final VoidCallback? onDismissed;

  /// Optional ✓ beside the ✕; [onAction] runs, then the toast closes.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Pinned `safe-area + 52` from the top with 12 side gutters (canvas
  /// `floating`), instead of laid out in flow.
  final bool _floating;

  const ZToastCard({
    super.key,
    required this.title,
    this.message,
    this.amount,
    this.kind = ZToastKind.success,
    this.duration = ZToast.defaultDuration,
    this.onDismissed,
    this.actionLabel,
    this.onAction,
  }) : _floating = false;

  const ZToastCard.floating({
    super.key,
    required this.title,
    this.message,
    this.amount,
    this.kind = ZToastKind.success,
    this.duration = ZToast.defaultDuration,
    this.onDismissed,
    this.actionLabel,
    this.onAction,
  }) : _floating = true;

  @override
  State<ZToastCard> createState() => _ZToastCardState();
}

class _ZToastCardState extends State<ZToastCard> with TickerProviderStateMixin {
  static const _maxWidth = 372.0;
  static const _floatTop = 52.0;
  static const _floatGutter = 12.0;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: ZGameMotion.dialogEnter,
  );
  late final AnimationController _drain = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _drain.addStatusListener((s) {
      if (s == AnimationStatus.completed) _close();
    });
    _drain.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (homeReducedMotion(context)) {
      _enter.value = 1;
    } else if (!_enter.isAnimating && _enter.value == 0) {
      _enter.forward();
    }
  }

  void _close() {
    if (_done) return;
    _done = true;
    widget.onDismissed?.call();
  }

  @override
  void dispose() {
    _enter.dispose();
    _drain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AnimatedBuilder(
      animation: _enter,
      child: _Card(
        title: widget.title,
        message: widget.message,
        amount: widget.amount,
        kind: widget.kind,
        drain: _drain,
        onClose: _close,
        actionLabel: widget.actionLabel,
        onAction: widget.onAction,
      ),
      builder: (context, child) {
        final t = _spring.transform(_enter.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -48 * (1 - t)),
            child: child,
          ),
        );
      },
    );
    // The overlay has no Material above it; without one text gets the debug
    // double underline.
    final framed = Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: card,
          ),
        ),
      ),
    );
    if (!widget._floating) return framed;
    return Stack(
      children: [
        PositionedDirectional(
          top: MediaQuery.paddingOf(context).top + _floatTop,
          start: _floatGutter,
          end: _floatGutter,
          child: framed,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? message;
  final String? amount;
  final ZToastKind kind;
  final Animation<double> drain;
  final VoidCallback onClose;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Card({
    required this.title,
    required this.message,
    required this.amount,
    required this.kind,
    required this.drain,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final accent = switch (kind) {
      ZToastKind.success => z.teal,
      ZToastKind.error => z.coral,
      ZToastKind.info => z.indigo,
      ZToastKind.coin => z.amber,
    };
    final hasMessage = message != null && message!.isNotEmpty;
    final hasAmount = amount != null && amount!.isNotEmpty;
    final text = hasMessage ? '$title. $message' : title;

    return Container(
      decoration: BoxDecoration(
        color: z.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: zs.outline, width: ZGame.outline),
        boxShadow: ZElevation.solidEdge(zs.outline, depth: 5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22 - ZGame.outline),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 12, 12),
              child: Row(
                children: [
                  _Badge(kind: kind, accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          container: true,
                          liveRegion: true,
                          label: text,
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontFamily: 'Vazirmatn',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  height: 1.35,
                                  leadingDistribution:
                                      TextLeadingDistribution.even,
                                  color: z.ink,
                                ),
                              ),
                              if (hasMessage) ...[
                                const SizedBox(height: 2),
                                Text(
                                  message!,
                                  style: TextStyle(
                                    fontFamily: 'Vazirmatn',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.6,
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
                                    color: z.ink60,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasAmount) ...[
                    const SizedBox(width: 12),
                    _AmountChip(amount: amount!),
                  ],
                  const SizedBox(width: 4),
                  if (actionLabel != null && onAction != null)
                    _ActionButton(
                      key: const ValueKey('z-toast-action'),
                      label: actionLabel!,
                      color: z.teal,
                      onTap: () {
                        onAction!();
                        onClose();
                      },
                    ),
                  _CloseButton(onTap: onClose),
                ],
              ),
            ),
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              height: 5,
              child: ColoredBox(
                color: zs.track,
                child: AnimatedBuilder(
                  animation: drain,
                  builder:
                      (context, _) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor: 1 - drain.value,
                          heightFactor: 1,
                          child: ColoredBox(color: accent),
                        ),
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

class _Badge extends StatelessWidget {
  final ZToastKind kind;
  final Color accent;

  const _Badge({required this.kind, required this.accent});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final glyph = switch (kind) {
      ZToastKind.success => CustomPaint(
        size: const Size(20, 20),
        painter: _GlyphPainter(_Glyph.check, zs.outline),
      ),
      ZToastKind.error => CustomPaint(
        size: const Size(18, 18),
        painter: _GlyphPainter(_Glyph.cross, zs.outline),
      ),
      ZToastKind.info => CustomPaint(
        size: const Size(18, 20),
        painter: _GlyphPainter(_Glyph.info, z.onIndigo),
      ),
      ZToastKind.coin => Text(
        '+',
        style: TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 17,
          fontWeight: FontWeight.w900,
          height: 1,
          color: zs.outline,
        ),
      ),
    };
    return ChunkyBox(
      circle: true,
      fill: accent,
      depth: ZGame.depthSm,
      width: 44,
      height: 44,
      alignment: Alignment.center,
      child: glyph,
    );
  }
}

enum _Glyph { check, cross, info }

class _GlyphPainter extends CustomPainter {
  final _Glyph glyph;
  final Color color;

  const _GlyphPainter(this.glyph, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case _Glyph.check:
        stroke.strokeWidth = 3.4;
        canvas.drawPath(
          Path()
            ..moveTo(4, 10.5)
            ..lineTo(8.2, 14.5)
            ..lineTo(16, 6),
          stroke,
        );
      case _Glyph.cross:
        stroke.strokeWidth = 3.4;
        canvas.drawPath(
          Path()
            ..moveTo(4, 4)
            ..lineTo(14, 14)
            ..moveTo(14, 4)
            ..lineTo(4, 14),
          stroke,
        );
      case _Glyph.info:
        canvas.drawCircle(const Offset(9, 4), 2.4, Paint()..color = color);
        stroke.strokeWidth = 3.6;
        canvas.drawLine(const Offset(9, 9), const Offset(9, 17), stroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// The toast's optional action: a ✓ beside the ✕. [label] is only for screen
/// readers.
class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: CustomPaint(
              size: const Size(20, 20),
              painter: _GlyphPainter(_Glyph.check, color),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String amount;

  const _AmountChip({required this.amount});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.wash,
      depth: 0,
      radius: 999,
      borderWidth: ZGame.outlineInner,
      highlight: false,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyBox(
            circle: true,
            fill: z.amber,
            depth: 0,
            borderWidth: 2,
            width: 14,
            height: 14,
          ),
          const SizedBox(width: 5),
          Text(
            amount,
            style: TextStyle(
              fontFamily: 'Vazirmatn',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1,
              color: z.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      button: true,
      label: 'بستن',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: CustomPaint(
              size: const Size(12, 12),
              painter: _ClosePainter(z.ink60),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClosePainter extends CustomPainter {
  final Color color;

  const _ClosePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(2, 2)
        ..lineTo(10, 10)
        ..moveTo(10, 2)
        ..lineTo(2, 10),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ClosePainter old) => old.color != color;
}
