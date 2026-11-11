import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';
import 'package:wordchain/features/rewards/view/widgets/reward_format.dart';

RewardItem _item(String kind, {String detail = '', int? variant}) =>
    RewardItem.fromJson({
      'id': 'r',
      'kind': kind,
      'detail': detail,
      'coins': 100,
      'claimed': false,
      'created_at': '2026-11-11T00:00:00Z',
      if (variant != null) 'daily_variant': variant,
    });

void main() {
  test('a classic Daily prize reads as before', () {
    expect(
      rewardFace(_item('daily_rank', detail: '1')).body,
      'در چالش دیروز رتبهٔ ۱ شدی! ۱۰۰ سکه هدیه بگیر.',
    );
    expect(
      rewardFace(_item('daily_done')).body,
      'برای شرکت در چالش دیروز ۱۰۰ سکه هدیه بگیر.',
    );
  });

  test('a harder Daily prize names its type', () {
    expect(
      rewardFace(_item('daily_rank', detail: '2', variant: 2)).body,
      'در چالش «حرف دوم» دیروز رتبهٔ ۲ شدی! ۱۰۰ سکه هدیه بگیر.',
    );
    expect(
      rewardFace(_item('daily_done', variant: 3)).body,
      'برای شرکت در چالش «حرف سوم» دیروز ۱۰۰ سکه هدیه بگیر.',
    );
  });

  test('claiming keeps the type', () {
    expect(_item('daily_done', variant: 3).asClaimed().dailyVariant, 3);
  });
}
