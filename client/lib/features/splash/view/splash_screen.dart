import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/theme/app_motion.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';

/// Launch splash: the wordmark tiles drop in one after another, starting with
/// «ز» (rightmost) and ending with «ر», then the title fades in and the app
/// continues to `/home`.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _letters = [
    ('ز', ZAccent.indigo, -5.0),
    ('ن', ZAccent.teal, 2.0),
    ('ج', ZAccent.amber, -2.0),
    ('ی', ZAccent.coral, 4.0),
    ('ر', ZAccent.indigo, -3.0),
  ];

  static const _total = Duration(milliseconds: 2600);
  static const _stagger = 0.085; // fraction of _total between tiles
  static const _tileSpan = 0.2;

  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total)
      ..forward().whenComplete(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted) context.go('/home');
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _deg(double d) => d * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final titleT = Curves.easeOut.transform(
              ((_c.value - 0.62) / 0.25).clamp(0.0, 1.0),
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: FittedBox(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _letters.length; i++) ...[
                          _tile(i),
                          if (i != _letters.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: ZSpacing.lg),
                Opacity(
                  opacity: titleT,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - titleT)),
                    child: Text(
                      'زنجیر',
                      style: TextStyle(
                        fontFamily: 'Vazirmatn',
                        fontWeight: FontWeight.w900,
                        fontSize: 34,
                        height: 1.2,
                        color: z.ink,
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: titleT,
                  child: Text(
                    'کلمه بساز، زنجیر را نگه دار',
                    style: TextStyle(
                      fontFamily: 'Vazirmatn',
                      fontSize: 14,
                      color: z.ink60,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tile(int i) {
    final start = i * _stagger;
    final t = ((_c.value - start) / _tileSpan).clamp(0.0, 1.0);
    final drop = ZMotion.tileDropCurve.transform(t);
    final (letter, accent, deg) = _letters[i];
    return Opacity(
      opacity: Curves.easeOut.transform((t * 2.5).clamp(0.0, 1.0)),
      child: Transform.translate(
        offset: Offset(0, -90 * (1 - drop)),
        child: LetterTile(
          letter: letter,
          accent: accent,
          size: 54,
          height: 68,
          radius: ZRadius.tileMax,
          fontSize: 34,
          rotation: _deg(deg) * drop + _deg(-14) * (1 - drop),
        ),
      ),
    );
  }
}
