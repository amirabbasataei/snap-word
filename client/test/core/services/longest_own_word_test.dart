import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/ai_opponent.dart';

void main() {
  const chain = ['کتاب', 'بازیگر', 'رنگ', 'ناآشنایان'];

  test('solo chain counts every word', () {
    expect(longestOwnWord(chain, 'solo'), 'ناآشنایان');
  });

  test('vs-AI ignores the AI\'s (odd-index) words', () {
    expect(longestOwnWord(chain, 'ai_hard'), 'کتاب');
  });

  test('empty chain has no longest word', () {
    expect(longestOwnWord(const [], 'ai_easy'), isNull);
  });
}
