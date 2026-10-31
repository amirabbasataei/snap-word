import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_rays.dart';
import 'package:wordchain/core/widgets/z_stroked_text.dart';

/// The picture that «اشتراک‌گذاری» sends: a 9:16 story card with the result
/// and — for a signed-in player — their invite code.
///
/// Laid out on a 360×640 grid; [ShareImageRenderer] captures it at pixel
/// ratio 3 → 1080×1920, the Instagram / Telegram story size. Always drawn in
/// the light theme, whatever the app is set to, so a shared image looks the
/// same for everyone. No network images, no animation: it is rendered
/// off-screen and must be ready on the first frame.
class ShareStoryCard extends StatelessWidget {
  static const size = Size(360, 640);

  /// Small line above the score: «نتیجهٔ من» / «چالش روزانهٔ ۱۲».
  final String heading;
  final int score;
  final int chainLength;

  /// The chain's words, oldest first; only the last few are drawn.
  final List<String> words;
  final ZMascotMood mood;

  /// The player's referral code; null (guest, or the fetch failed) hides the
  /// invite block and leaves only the brand.
  final String? inviteCode;

  const ShareStoryCard({
    super.key,
    required this.heading,
    required this.score,
    required this.chainLength,
    required this.words,
    this.mood = ZMascotMood.happy,
    this.inviteCode,
  });

  /// How many words of the chain fit between the mascot and the invite block.
  static const maxWords = 4;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light,
      child: Builder(
        builder: (context) {
          final z = context.z;
          final zs = context.zs;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
                disableAnimations: true,
              ),
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'Vazirmatn'),
                child: SizedBox.fromSize(
                  size: size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [zs.sky1, zs.sky2, zs.sky3],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 40,
                        left: -60,
                        right: -60,
                        height: 480,
                        child: CustomPaint(
                          painter: ZRaysPainter(
                            z.amber.withValues(alpha: .32),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 48, 28, 72),
                        child: Column(
                          children: [
                            ZStrokedText(
                              'زنجیر',
                              fontSize: 40,
                              fill: z.amber,
                              stroke: 6,
                            ),
                            const SizedBox(height: 4),
                            ZMascot(
                              mood: mood,
                              size: 96,
                              shadow: false,
                              animate: false,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              heading,
                              style: ZTypography.button.copyWith(
                                fontSize: 15,
                                color: z.ink60,
                              ),
                            ),
                            _Score(score: score, chainLength: chainLength),
                            const SizedBox(height: 12),
                            _Chain(words: words),
                            const Spacer(),
                            if (inviteCode != null)
                              _InviteBlock(code: inviteCode!)
                            else
                              Text(
                                'بازی زنجیرهٔ کلمه‌ها',
                                style: ZTypography.button.copyWith(
                                  fontSize: 16,
                                  color: z.ink60,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Score extends StatelessWidget {
  final int score;
  final int chainLength;

  const _Score({required this.score, required this.chainLength});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      children: [
        Text(
          formatPersianNumber(score),
          style: ZTypography.display.copyWith(fontSize: 52, color: z.ink),
        ),
        Text(
          'امتیاز · زنجیر ${toPersianDigits(chainLength)} کلمه‌ای',
          style: ZTypography.button.copyWith(fontSize: 15, color: z.ink60),
        ),
      ],
    );
  }
}

/// The last words of the chain as stacked chunky pills, alternating colours,
/// with a short link between each pair.
class _Chain extends StatelessWidget {
  final List<String> words;

  const _Chain({required this.words});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final shown =
        words.length > ShareStoryCard.maxWords
            ? words.sublist(words.length - ShareStoryCard.maxWords)
            : words;
    if (shown.isEmpty) return const SizedBox.shrink();
    final fills = [
      (z.indigo, z.indigoDeep, z.onIndigo),
      (z.teal, z.tealDeep, z.onTeal),
      (z.coral, z.coralDeep, z.onCoral),
    ];
    final offset = words.length - shown.length;
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final (fill, deep, on) = fills[(offset + i) % fills.length];
      if (i > 0) {
        children.add(
          Container(
            width: 6,
            height: 6,
            color: context.zs.outline,
          ),
        );
      }
      children.add(
        ChunkyBox(
          fill: fill,
          deep: deep,
          depth: ZGame.depthSm,
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 3),
          child: Text(
            shown[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZTypography.chainWordActive.copyWith(
              fontSize: 18,
              color: on,
            ),
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _InviteBlock extends StatelessWidget {
  final String code;

  const _InviteBlock({required this.code});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      deep: z.line,
      depth: ZGame.depthMd,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'با کد دعوت من ثبت‌نام کن و سکهٔ هدیه بگیر',
            textAlign: TextAlign.center,
            style: ZTypography.button.copyWith(fontSize: 14, color: z.ink),
          ),
          const SizedBox(height: 8),
          ChunkyBox(
            fill: z.indigo,
            deep: z.indigoDeep,
            depth: ZGame.depthSm,
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 6),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                code,
                style: ZTypography.display.copyWith(
                  fontSize: 32,
                  letterSpacing: 6,
                  color: z.onIndigo,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
