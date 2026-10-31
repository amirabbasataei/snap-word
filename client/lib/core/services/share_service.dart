import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wordchain/core/services/analytics_service.dart';
import 'package:wordchain/core/services/share_image_renderer.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/share/view/share_story_card.dart';

class DailyChallengeResult {
  final int dayNumber;
  final int score;
  final int chainLength;
  final List<String> wordChain;

  const DailyChallengeResult({
    required this.dayNumber,
    required this.score,
    required this.chainLength,
    required this.wordChain,
  });
}

typedef ShareFiles = Future<void> Function(String path, String text);

class ShareService {
  /// The player's own referral code, or null for a guest / when it cannot be
  /// fetched. Never throws; sharing must work without it.
  final Logger _log = Logger();
  final Future<String?> Function() _inviteCode;
  final ShareImageRenderer _renderer;
  final ShareFiles _shareFile;

  ShareService({
    Future<String?> Function()? inviteCode,
    ShareImageRenderer renderer = const ShareImageRenderer(),
    ShareFiles? shareFile,
  }) : _inviteCode = inviteCode ?? (() async => null),
       _renderer = renderer,
       _shareFile = shareFile ?? _systemShareFile;

  static Future<void> _systemShareFile(String path, String text) async {
    await Share.shareXFiles([XFile(path, mimeType: 'image/png')], text: text);
  }

  Future<void> shareDaily(
    BuildContext context,
    DailyChallengeResult result,
  ) async {
    trackEvent(AnalyticsEvent.share, {'kind': 'daily'});
    final code = await _safeCode();
    if (!context.mounted) return;
    final sent = await _shareCard(
      context,
      name: 'zanjir_daily_${result.dayNumber}',
      card: ShareStoryCard(
        heading: 'چالش روزانهٔ ${toPersianDigits(result.dayNumber)}',
        score: result.score,
        chainLength: result.chainLength,
        words: result.wordChain,
        inviteCode: code,
      ),
      caption: _caption(
        'چالش روزانهٔ زنجیر رو ${formatPersianNumber(result.score)} امتیاز زدم!',
        code,
      ),
    );
    if (sent) return;
    final chain = result.wordChain.join(' → ');
    await Share.share(
      'زنجیر · چالش روزانهٔ ${toPersianDigits(result.dayNumber)}\n'
      'امتیاز: ${formatPersianNumber(result.score)} · طول زنجیر: '
      '${toPersianDigits(result.chainLength)} کلمه\n$chain',
    );
  }

  Future<void> shareMatch(
    BuildContext context, {
    required int score,
    required int chainLength,
    List<String> words = const [],
    bool? won,
  }) async {
    trackEvent(AnalyticsEvent.share, {'kind': 'match'});
    final code = await _safeCode();
    if (!context.mounted) return;
    final sent = await _shareCard(
      context,
      name: 'zanjir_match',
      card: ShareStoryCard(
        heading: won == true ? 'برنده شدم!' : 'نتیجهٔ من',
        score: score,
        chainLength: chainLength,
        words: words,
        mood: won == false ? ZMascotMood.sad : ZMascotMood.happy,
        inviteCode: code,
      ),
      caption: _caption(
        'زنجیر رو پاره کردم! امتیاز: ${formatPersianNumber(score)} · '
        'طول زنجیر: ${toPersianDigits(chainLength)} کلمه',
        code,
      ),
    );
    if (sent) return;
    await Share.share(
      'زنجیر رو پاره کردم! امتیاز: ${formatPersianNumber(score)} · '
      'طول زنجیر: ${toPersianDigits(chainLength)} کلمه',
    );
  }

  String _caption(String line, String? code) =>
      code == null ? line : '$line\nکد دعوت من در زنجیر: $code';

  Future<String?> _safeCode() async {
    try {
      final code = await _inviteCode().timeout(const Duration(seconds: 4));
      return (code == null || code.isEmpty) ? null : code;
    } catch (_) {
      return null;
    }
  }

  /// Renders [card] and opens the share sheet with it. False when the image
  /// could not be made, so the caller falls back to plain text.
  Future<bool> _shareCard(
    BuildContext context, {
    required String name,
    required ShareStoryCard card,
    required String caption,
  }) async {
    try {
      final path = await _renderer.renderToFile(
        context,
        card,
        size: ShareStoryCard.size,
        name: name,
      );
      await _shareFile(path, caption);
      return true;
    } catch (e, st) {
      _log.w('share image failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Invite text for social apps and SMS. The code is what the friend enters
  /// at signup (100 coins) or in Profile → Settings (50 coins).
  Future<void> shareInvite({required String code}) async {
    final text = '''بیا با هم زنجیر کلمه بازی کنیم! 🔗
موقع ثبت‌نام این کد دعوت رو وارد کن و سکهٔ هدیه بگیر: $code
دانلود و بازی: wordchain.app''';
    trackEvent(AnalyticsEvent.share, {'kind': 'invite'});
    await Share.share(text);
  }
}
