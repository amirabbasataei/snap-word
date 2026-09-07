import 'dart:collection';

import 'package:flutter/services.dart';

class DictionaryService {
  static const _assetPath = 'assets/words/fa.txt';
  static const _minLength = 3;

  /// Zero-width non-joiner — some Persian keyboards insert it inside
  /// compound words (e.g. "می‌روم"). It is not itself a letter, so it must
  /// be stripped before reading off a word's last letter.
  static const _zwnj = '‌';

  /// Persian letters (incl. hamza forms) plus ZWNJ, which is legal *within*
  /// a word (e.g. "می‌روم") even though it carries no letter value itself.
  /// Code points, in order: ء آ أ ؤ (0621-0624), ئ ا ب (0626-0628),
  /// ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ (062A-063A), ف ق (0641-0642),
  /// ل م ن ه و (0644-0648), پ (067E), چ (0686), ژ (0698), ک (06A9),
  /// گ (06AF), ی (06CC), ZWNJ (200C).
  static final RegExp _allowedChars = RegExp(
    '^[ء-ؤئ-بت-غف-ق'
    'ل-وپچژکگی‌]+\$',
  );

  late final HashSet<String> _words;

  Set<String> get words => _words;

  Future<void> load() async {
    final raw = await rootBundle.loadString(_assetPath);
    _words = HashSet<String>.from(
      raw.split('\n').map((w) => w.trim()).where((w) => w.isNotEmpty),
    );
  }

  bool isValid(String word) {
    final normalized = word.trim();
    if (normalized.length < _minLength) return false;
    if (!_allowedChars.hasMatch(normalized)) return false;
    return _words.contains(normalized);
  }

  List<String> suggestWords(String startLetter) {
    final letter = startLetter.trim();
    if (letter.isEmpty) return const [];
    return _words
        .where((w) => w.startsWith(letter) && w.length >= _minLength)
        .take(5)
        .toList();
  }

  /// Returns the last meaningful letter of a Persian word, stripping any
  /// zero-width non-joiner first — some inputs and word lists include one
  /// adjacent to the final letter, and it must not be mistaken for a letter
  /// when determining the next required starting letter.
  static String lastLetterOf(String word) {
    final cleaned = word.trimRight().replaceAll(_zwnj, '');
    if (cleaned.isEmpty) return '';
    return cleaned[cleaned.length - 1];
  }
}
