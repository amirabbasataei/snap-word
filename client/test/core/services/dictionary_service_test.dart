import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/dictionary_service.dart';

void main() {
  group('DictionaryService.lastLetterOf (ZWNJ handling)', () {
    test('plain word returns its real last letter', () {
      expect(DictionaryService.lastLetterOf('کتاب'), 'ب');
    });

    test('trailing ZWNJ is stripped rather than read as a letter', () {
      expect(DictionaryService.lastLetterOf('کتاب‌'), 'ب');
    });

    test(
      'compound word with embedded ZWNJ (می‌روم) yields the real last letter',
      () {
        // "می" + ZWNJ + "روم" — the ZWNJ sits mid-word; the last letter is
        // the م from "روم", not affected by stripping, but stripping must
        // not corrupt the rest of the word either.
        expect(DictionaryService.lastLetterOf('می‌روم'), 'م');
      },
    );

    test('another common ZWNJ compound (نمی‌دانم)', () {
      expect(DictionaryService.lastLetterOf('نمی‌دانم'), 'م');
    });

    test('trailing whitespace and ZWNJ together are both stripped', () {
      expect(DictionaryService.lastLetterOf('کتاب‌  '), 'ب');
    });

    test('empty string returns empty string', () {
      expect(DictionaryService.lastLetterOf(''), '');
    });

    test('a lone ZWNJ returns empty string', () {
      expect(DictionaryService.lastLetterOf('‌'), '');
    });
  });

  group('DictionaryService.isValid (with the real bundled fa.txt asset)', () {
    late DictionaryService dictionaryService;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dictionaryService = DictionaryService();
      await dictionaryService.load();
    });

    test('loads a non-trivial number of words', () {
      expect(dictionaryService.words.length, greaterThan(100000));
    });

    test('accepts real Persian words', () {
      for (final w in ['کتاب', 'باران', 'سلام', 'دوست', 'روباه', 'تهران']) {
        expect(dictionaryService.isValid(w), isTrue, reason: w);
      }
    });

    test('rejects words shorter than the minimum length', () {
      expect(dictionaryService.isValid('او'), isFalse);
      expect(dictionaryService.isValid('و'), isFalse);
    });

    test('rejects words with Latin letters', () {
      expect(dictionaryService.isValid('ketab'), isFalse);
    });

    test('rejects words with digits or punctuation', () {
      expect(dictionaryService.isValid('کتاب۱'), isFalse);
      expect(dictionaryService.isValid('کتاب-درسی'), isFalse);
    });

    test('rejects nonsense words not present in the dictionary', () {
      expect(dictionaryService.isValid('زکسلوپ'), isFalse);
    });

    test('trims surrounding whitespace before checking', () {
      expect(dictionaryService.isValid('  کتاب  '), isTrue);
    });
  });
}
