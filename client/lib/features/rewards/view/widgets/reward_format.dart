import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';

/// How one prize reads on its card: the title and line of text, and the glyph
/// on the coloured disc (the canvas puts a number or a letter there).
class RewardFace {
  final String title;
  final String body;
  final String glyph;
  final ZDialogAccent accent;

  const RewardFace({
    required this.title,
    required this.body,
    required this.glyph,
    required this.accent,
  });
}

/// Text and disc of [item], by `inbox_rewards.kind`. [RewardItem.detail] is a
/// friend's username (referral), a streak length or a rank, depending on it.
RewardFace rewardFace(RewardItem item) {
  final coins = toPersianDigits(item.coins);
  final number = toPersianDigits(item.detail);
  switch (item.kind) {
    case 'streak':
      return RewardFace(
        title: 'پاداش روزهای پیاپی',
        body: '$number روز پیاپی بازی کردی! $coins سکه هدیه بگیر.',
        glyph: number,
        accent: ZDialogAccent.amber,
      );
    case 'weekly_rank':
      return RewardFace(
        title: 'پاداش جدول هفتگی',
        body: 'در جدول هفتگی رتبهٔ $number شدی! $coins سکه هدیه بگیر.',
        glyph: number,
        accent: ZDialogAccent.indigo,
      );
    case 'daily_rank':
      return RewardFace(
        title: 'جایزهٔ چالش روزانه',
        body: 'در چالش دیروز رتبهٔ $number شدی! $coins سکه هدیه بگیر.',
        glyph: number,
        accent: ZDialogAccent.teal,
      );
    case 'daily_done':
      return RewardFace(
        title: 'پاداش چالش روزانه',
        body: 'برای شرکت در چالش دیروز $coins سکه هدیه بگیر.',
        glyph: 'چ',
        accent: ZDialogAccent.teal,
      );
    case 'admin_gift':
      return RewardFace(
        title: 'هدیهٔ زنجیر',
        body: 'تیم زنجیر برایت $coins سکه هدیه فرستاده است.',
        glyph: 'ز',
        accent: ZDialogAccent.coral,
      );
    case 'word_suggestion':
      // detail = the approved word (may be anything Persian; isolate it).
      final word = item.detail.isEmpty ? '' : ' «\u2068${item.detail}\u2069»';
      return RewardFace(
        title: 'پاداش پیشنهاد کلمه',
        body:
            'کلمهٔ$word که پیشنهاد دادی به بازی اضافه شد. $coins سکه هدیه بگیر!',
        glyph: 'ک',
        accent: ZDialogAccent.teal,
      );
    case 'daily_login':
      return RewardFace(
        title: 'پاداش ورود روزانه',
        body: 'برای سر زدن امروز $coins سکه هدیه بگیر.',
        glyph: 'و',
        accent: ZDialogAccent.amber,
      );
    default:
      // A username can be Latin; the isolate keeps the Persian around it in order.
      final name = item.detail.isEmpty ? 'دوستت' : '\u2068${item.detail}\u2069';
      return RewardFace(
        title: 'هدیهٔ دعوت',
        body: '$name با کد دعوت تو وارد بازی شد. $coins سکه هدیه بگیر!',
        glyph: '+',
        accent: ZDialogAccent.indigo,
      );
  }
}

/// Unclaimed prizes first, claimed ones after; each group keeps the server's
/// order.
List<RewardItem> sortRewards(List<RewardItem> items) => [
  ...items.where((i) => !i.claimed),
  ...items.where((i) => i.claimed),
];

int readyCoins(List<RewardItem> items) =>
    items.where((i) => !i.claimed).fold(0, (sum, i) => sum + i.coins);
