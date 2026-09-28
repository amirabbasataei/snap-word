import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/ai_opponent.dart';
import 'package:wordchain/core/services/dictionary_service.dart';

void main() {
  late DictionaryService dictionary;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dictionary = DictionaryService();
    await dictionary.load();
  });

  test('trap letters each start at least one real word', () {
    for (final letter in aiTrapLetters) {
      expect(dictionary.words.any((w) => w.startsWith(letter) && w.length >= 3), isTrue,
          reason: letter);
    }
  });

  test('trapPref=1 picks a trap-ending word when one exists', () {
    // Find a starting letter that has at least one trap-ending word.
    final seed = dictionary.words.firstWhere(
        (w) => w.length >= 3 && aiTrapLetters.contains(DictionaryService.lastLetterOf(w)));
    final word = selectAIWord(
      letter: seed[0],
      usedWords: {},
      dictionary: dictionary,
      difficulty: const AIDifficultyConfig(
          delayMs: 0, mistakeRate: 0, minWordLength: 3, trapPref: 1, preferLongest: false),
    );
    expect(word, isNotNull);
    expect(word![0], seed[0]);
    expect(aiTrapLetters, contains(DictionaryService.lastLetterOf(word)));
  });
}
