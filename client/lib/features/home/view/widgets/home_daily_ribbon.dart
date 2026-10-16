import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_icons.dart';

/// Amber ribbon with the day's Jalali date and a live countdown to the next
/// Iran-midnight rollover. Tapping opens the Daily Challenge.
class HomeDailyRibbon extends StatefulWidget {
  /// Show the coral "new" dot (the challenge hasn't been played today).
  final bool showDot;
  final VoidCallback onTap;

  /// Clock injection for tests (defaults to the wall clock).
  final DateTime Function()? clock;

  const HomeDailyRibbon({
    super.key,
    required this.showDot,
    required this.onTap,
    this.clock,
  });

  static const size = Size(172, 62);

  /// `۰۸:۱۲:۴۵` until the next Iran midnight.
  static String countdown(DateTime now) {
    final left = untilIranMidnight(now);
    String two(int v) => v.toString().padLeft(2, '0');
    return toPersianDigits(
      '${two(left.inHours)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}',
    );
  }

  /// `۲۴ مهر` — today's Jalali day and month in Iran time.
  static String dateLabel(DateTime now) {
    final iran = now.toUtc().add(iranOffset);
    final j = Jalali.fromDateTime(DateTime(iran.year, iran.month, iran.day));
    return '${toPersianDigits(j.day)} ${j.formatter.mN}';
  }

  @override
  State<HomeDailyRibbon> createState() => _HomeDailyRibbonState();
}

class _HomeDailyRibbonState extends State<HomeDailyRibbon> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = _read();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = _read());
    });
  }

  DateTime _read() => (widget.clock ?? DateTime.now)();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Semantics(
      button: true,
      label: 'چالش روزانه',
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.fromSize(
          size: HomeDailyRibbon.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Folded tails behind the band.
              Positioned(
                right: -24,
                top: 16,
                child: _Tail(
                  flip: false,
                  fill: z.amberDeep,
                  stroke: zs.outline,
                ),
              ),
              Positioned(
                left: -24,
                top: 16,
                child: _Tail(flip: true, fill: z.amberDeep, stroke: zs.outline),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: ChunkyBox(
                  fill: z.amber,
                  deep: z.amberDeep,
                  depth: ZGame.depthMd,
                  radius: 12,
                  width: 172,
                  height: 56,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'چالش روزانه',
                            style: ZTypography.button.copyWith(
                              fontSize: 15,
                              height: 1.1,
                              color: z.onAmber,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Date chip: ink on surface (the canvas used onAmber,
                          // which is near-invisible on the dark surface).
                          Container(
                            padding: const EdgeInsets.fromLTRB(5, 2, 5, 3),
                            decoration: BoxDecoration(
                              color: z.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: zs.outline, width: 2),
                            ),
                            child: Text(
                              HomeDailyRibbon.dateLabel(_now),
                              style: ZTypography.button.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: z.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.fromLTRB(9, 2, 9, 3),
                        decoration: BoxDecoration(
                          color: z.inkSurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HomeSvg(
                              HomeGlyph.clock,
                              width: 11,
                              height: 11,
                              color: z.onInkSurface,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              HomeDailyRibbon.countdown(_now),
                              textDirection: TextDirection.ltr,
                              style: ZTypography.button.copyWith(
                                fontSize: 12.5,
                                height: 1.2,
                                color: z.onInkSurface,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showDot)
                Positioned(
                  left: -6,
                  top: -8,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: z.coral,
                      shape: BoxShape.circle,
                      // The canvas dot is ringed in surface, not outline.
                      border: Border.all(color: z.surface, width: 3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tail extends StatelessWidget {
  final bool flip;
  final Color fill;
  final Color stroke;

  const _Tail({required this.flip, required this.fill, required this.stroke});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(34, 38),
      painter: _TailPainter(flip: flip, fill: fill, stroke: stroke),
    );
  }
}

/// Swallow-tail of the ribbon: `M0 0H34L24 19L34 38H0Z` (mirrored for the
/// start side).
class _TailPainter extends CustomPainter {
  final bool flip;
  final Color fill;
  final Color stroke;

  const _TailPainter({
    required this.flip,
    required this.fill,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(34, 0)
          ..lineTo(24, 19)
          ..lineTo(34, 38)
          ..lineTo(0, 38)
          ..close();
    if (flip) {
      canvas.translate(34, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.flip != flip || old.fill != fill || old.stroke != stroke;
}
