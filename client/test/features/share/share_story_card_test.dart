import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/share_image_renderer.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/share/view/share_story_card.dart';

import '../../helpers/z_test_app.dart';

const _words = ['سنگ', 'گلاب', 'بهار', 'رودخانه', 'هنرمند', 'دریا'];

/// Fake renderer: the real one needs path_provider; the tests that exercise
/// ShareService only care what happens around it.
class _OkRenderer extends ShareImageRenderer {
  @override
  Future<String> renderToFile(
    BuildContext context,
    Widget widget, {
    required Size size,
    required String name,
    double pixelRatio = 3,
  }) async => '/tmp/$name.png';
}

Future<BuildContext> _pump(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    zTestApp(
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    ),
  );
  return ctx;
}

/// The renderer awaits real frames, which a widget test only produces when it
/// pumps: run the capture in real async time and pump until it finishes.
Future<T> _renderWhilePumping<T>(
  WidgetTester tester,
  Future<T> Function() render,
) async {
  final result = await tester.runAsync<T>(() async {
    var done = false;
    final future = render().whenComplete(() => done = true);
    while (!done) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    return future;
  });
  return result as T;
}

void main() {
  setUpAll(loadVazirmatn);

  testWidgets('renders a 1080x1920 PNG off-screen', (tester) async {
    final ctx = await _pump(tester);
    final out = Platform.environment['SHARE_CARD_OUT'];
    for (final withCode in [true, false]) {
      final bytes = await _renderWhilePumping(
        tester,
        () => const ShareImageRenderer().renderPng(
          ctx,
          ShareStoryCard(
            heading: 'برنده شدم!',
            score: 1840,
            chainLength: 14,
            words: _words,
            inviteCode: withCode ? 'K7M2QX' : null,
          ),
          size: ShareStoryCard.size,
        ),
      );
      // PNG signature, then IHDR width/height.
      expect(bytes.sublist(1, 4), [0x50, 0x4E, 0x47]);
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint32(16), 1080);
      expect(bd.getUint32(20), 1920);
      if (out != null) {
        File('$out/card_${withCode ? 'code' : 'guest'}.png').writeAsBytesSync(bytes);
      }
    }
  });

  group('ShareService', () {
    testWidgets('shares the image with the invite code in the caption', (
      tester,
    ) async {
      final ctx = await _pump(tester);
      final sent = <(String, String)>[];
      final service = ShareService(
        inviteCode: () async => 'K7M2QX',
        renderer: _OkRenderer(),
        shareFile: (p, t) async => sent.add((p, t)),
      );
      await service.shareMatch(ctx, score: 100, chainLength: 3, words: _words);
      expect(sent, hasLength(1));
      expect(sent.single.$1, endsWith('.png'));
      expect(sent.single.$2, contains('K7M2QX'));
    });

    testWidgets('a guest still shares the image, without a code', (
      tester,
    ) async {
      final ctx = await _pump(tester);
      final sent = <(String, String)>[];
      final service = ShareService(
        inviteCode: () async => null,
        renderer: _OkRenderer(),
        shareFile: (p, t) async => sent.add((p, t)),
      );
      await service.shareDaily(
        ctx,
        const DailyChallengeResult(
          dayNumber: 5,
          score: 90,
          chainLength: 3,
          wordChain: _words,
        ),
      );
      expect(sent, hasLength(1));
      expect(sent.single.$2, isNot(contains('کد دعوت')));
    });

    testWidgets('a failing code lookup does not block sharing', (tester) async {
      final ctx = await _pump(tester);
      final sent = <(String, String)>[];
      final service = ShareService(
        inviteCode: () async => throw Exception('offline'),
        renderer: _OkRenderer(),
        shareFile: (p, t) async => sent.add((p, t)),
      );
      await service.shareMatch(ctx, score: 1, chainLength: 1);
      expect(sent, hasLength(1));
    });

    testWidgets('card story keeps only the last words', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        zTestApp(
          const Center(
            child: ShareStoryCard(
              heading: 'x',
              score: 1,
              chainLength: 6,
              words: _words,
              mood: ZMascotMood.sad,
            ),
          ),
        ),
      );
      expect(find.text('سنگ'), findsNothing);
      expect(find.text('دریا'), findsOneWidget);
    });
  });
}
