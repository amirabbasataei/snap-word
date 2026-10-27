import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';
import 'package:wordchain/features/rewards/view/widgets/reward_format.dart';

void main() {
  test('an approved word suggestion reads as its own prize, not an invite', () {
    final face = rewardFace(
      RewardItem(
        id: 'r1',
        kind: 'word_suggestion',
        detail: 'آزمونک',
        coins: 25,
        claimed: false,
        createdAt: DateTime(2026, 10, 27),
      ),
    );
    expect(face.title, 'پاداش پیشنهاد کلمه');
    expect(face.body, contains('آزمونک'));
    expect(face.body, contains(toPersianDigits(25)));
    expect(face.body, isNot(contains('دعوت')));
    expect(face.glyph, 'ک');
  });

  test('a prize without its word still reads sensibly', () {
    final face = rewardFace(
      RewardItem(id: 'r2', kind: 'word_suggestion', detail: '', coins: 25, claimed: false, createdAt: DateTime(2026, 10, 27)),
    );
    expect(face.body, contains('پیشنهاد دادی'));
    expect(face.body, isNot(contains('«')));
  });
}
