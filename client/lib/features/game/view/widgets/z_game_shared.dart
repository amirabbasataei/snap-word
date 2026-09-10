import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';

/// Shared pieces of the ZSolo/ZPlay game screens — header back button,
/// timer row, powerup tile atom, dashed "next word" tile, and the restyled
/// word-input bar. Kept out of the legacy (unmigrated) multiplayer screen.

/// Back/close button — 34×34 rounded square, `ink60` arrow on `paper`.
class ZBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const ZBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.paper,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: z.line),
        ),
        child: Icon(Icons.arrow_forward, size: 16, color: z.ink60),
      ),
    );
  }
}

/// Confirm-and-end dialog shared by ZSolo/ZPlay's back button.
void zShowEndGameDialog(BuildContext context) {
  final z = context.z;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: z.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZRadius.cardMax),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('پایان بازی؟',
                style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 17)),
            const SizedBox(height: ZSpacing.sm),
            Text(
              'پیشرفت فعلی ذخیره می‌شود.',
              style: ZTypography.body.copyWith(color: z.ink60),
            ),
            const SizedBox(height: ZSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: NeutralButton(
                    label: 'ادامه بازی',
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: AccentButton(
                    accent: ZAccentColor.coral,
                    label: 'پایان بازی',
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      context.read<GameBloc>().add(const GameEnded());
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Numeric countdown + track bar — the turn-timer row atop ZSolo/ZPlay.
class ZTimerRow extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;

  const ZTimerRow({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final fraction =
        totalSeconds <= 0 ? 0.0 : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: ZSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              toPersianDigits(secondsRemaining.toString().padLeft(2, '0')),
              style: ZTypography.cardTitle.copyWith(color: z.coral, fontSize: 15),
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZRadius.chip),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: z.wash,
                valueColor: AlwaysStoppedAnimation(z.coral),
              ),
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Text('ثانیه', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
        ],
      ),
    );
  }
}

/// The hint power-up's glyph — a small indigo badge (matches the canvas's
/// nested `<span>` exactly; the bare "؟" text alone is invisible against
/// the tile's `paper` background since `onIndigo` is white/near-white).
class ZHintIcon extends StatelessWidget {
  const ZHintIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      width: 24,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: z.indigo, borderRadius: BorderRadius.circular(8)),
      child: Text('؟', style: TextStyle(color: z.onIndigo, fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }
}

/// A single power-up slot: icon glyph, top-leading badge count, label below.
class ZPowerupTile extends StatelessWidget {
  final Widget icon;
  final int count;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const ZPowerupTile({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Expanded(
      child: Column(
        children: [
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: z.paper,
                    borderRadius: BorderRadius.circular(ZRadius.tileMax),
                    border: Border.all(color: z.line),
                    boxShadow: enabled
                        ? ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth)
                        : null,
                  ),
                  child: Opacity(opacity: enabled ? 1 : 0.4, child: icon),
                ),
                PositionedDirectional(
                  top: -5,
                  start: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: z.ink, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      toPersianDigits(count),
                      style: TextStyle(
                        color: z.paper,
                        fontWeight: FontWeight.w800,
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: ZTypography.metaLabel.copyWith(color: z.ink60, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

/// Dashed-border letter tile — the "type your next word" placeholder that
/// closes both ZSolo's and ZPlay's chain views.
class ZDashedTile extends StatelessWidget {
  final String letter;
  final double size;

  const ZDashedTile({super.key, required this.letter, this.size = ZTileSize.prompt});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return CustomPaint(
      painter: _DashedRRectPainter(radius: 10, color: z.line),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            letter,
            style: ZTypography.chainWordActive.copyWith(color: z.ink40, fontSize: size * 0.5),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final double radius;
  final Color color;

  const _DashedRRectPainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final dashPath = Path();
    const dashWidth = 4.0;
    const dashGap = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        dashPath.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + dashGap;
      }
    }
    canvas.drawPath(
      dashPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// Restyled word-input bar — same functional contract as the legacy
/// `WordInput` (controller/focus/submit), redrawn on tokens: rounded input
/// with a 2px `ink` border + coral caret bar, `teal` send tile with a
/// solid offset edge.
class ZWordInput extends StatefulWidget {
  final String? startLetter;
  final bool enabled;
  final String? hintWord;
  final void Function(String word) onSubmit;
  final bool isOpponentThinking;
  final String opponentLabel;

  const ZWordInput({
    super.key,
    this.startLetter,
    required this.enabled,
    this.hintWord,
    required this.onSubmit,
    this.isOpponentThinking = false,
    this.opponentLabel = 'حریف',
  });

  @override
  State<ZWordInput> createState() => _ZWordInputState();
}

class _ZWordInputState extends State<ZWordInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(ZWordInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hintWord != null && widget.hintWord != oldWidget.hintWord) {
      _controller.text = widget.hintWord!;
      _controller.selection =
          TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final word = _controller.text.trim();
    if (word.isEmpty || !widget.enabled) return;
    widget.onSubmit(word);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;

    if (widget.isOpponentThinking) {
      return Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.paper,
          borderRadius: BorderRadius.circular(ZRadius.cardMin),
          border: Border.all(color: z.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: z.ink40),
            ),
            const SizedBox(width: ZSpacing.sm),
            Text(
              '${widget.opponentLabel} در حال فکر کردن…',
              style: ZTypography.body.copyWith(color: z.ink60, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: z.paper,
              borderRadius: BorderRadius.circular(ZRadius.cardMin),
              border: Border.all(color: z.ink, width: 2),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              textAlign: TextAlign.start,
              cursorColor: z.coral,
              cursorWidth: 2,
              style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 19),
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                isCollapsed: true,
                hintText: widget.startLetter != null
                    ? 'کلمه‌ای با «${widget.startLetter}»…'
                    : 'اولین کلمه رو بنویس…',
                hintStyle: ZTypography.body.copyWith(color: z.ink40),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
        const SizedBox(width: ZSpacing.sm),
        GestureDetector(
          onTap: widget.enabled ? _submit : null,
          child: Container(
            width: 64,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.enabled ? z.teal : z.wash,
              borderRadius: BorderRadius.circular(ZRadius.cardMin),
              boxShadow: widget.enabled
                  ? ZElevation.solidEdge(z.tealDeep, depth: ZElevation.buttonDepth)
                  : null,
            ),
            child: Text(
              'بفرست',
              style: ZTypography.button.copyWith(
                color: widget.enabled ? z.onTeal : z.ink40,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
