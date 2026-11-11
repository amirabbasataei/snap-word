import 'dart:collection';

import 'package:flutter/services.dart';

/// One word's desired state from the server's dictionary delta
/// (`GET /dictionary/delta`): [present] false = removed from the dictionary,
/// [aiBlocked] = still valid for the player but never played by the AI.
class DictionaryChange {
  final String word;
  final bool present;
  final bool aiBlocked;

  const DictionaryChange({
    required this.word,
    required this.present,
    required this.aiBlocked,
  });
}

class DictionaryService {
  static const _assetPath = 'assets/words/fa.txt';

  /// Mirrors `config.MinWordLength` / `GameConstants.minWordLength`.
  static const _minLength = 2;

  /// Hints favour words of at least this many letters; shorter ones are only
  /// offered when nothing longer is left.
  static const _hintPreferredLength = 3;

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
  final HashSet<String> _aiBlocked = HashSet<String>();

  DictionaryService();

  /// A dictionary over exactly [words] (tests).
  DictionaryService.withWords(Iterable<String> words) {
    _words = HashSet<String>.from(words);
  }

  Set<String> get words => _words;

  /// Words the AI must never play (still valid when the player types them).
  Set<String> get aiBlocked => _aiBlocked;

  /// Folds the server's delta over the bundled list. Later entries for the
  /// same word win; adding a word the asset already has is harmless.
  void applyChanges(Iterable<DictionaryChange> changes) {
    for (final c in changes) {
      if (c.present) {
        _words.add(c.word);
      } else {
        _words.remove(c.word);
      }
      if (c.aiBlocked) {
        _aiBlocked.add(c.word);
      } else {
        _aiBlocked.remove(c.word);
      }
    }
  }

  Future<void> load() async {
    final raw = await rootBundle.loadString(_assetPath);
    _words = HashSet<String>.from(
      raw.split('\n').map((w) => w.trim()).where((w) => w.isNotEmpty),
    );
  }

  bool isValid(String word) {
    final normalized = word.trim();
    if (normalized.length < _minLength) return false;
    if (!hasValidChars(normalized)) return false;
    return _words.contains(normalized);
  }

  /// Exposed so callers (e.g. `GameBloc`) can distinguish an
  /// `invalid_characters` rejection from a `not_in_dictionary` one instead
  /// of collapsing both into a single `isValid` check.
  static bool hasValidChars(String word) => _allowedChars.hasMatch(word);

  /// Valid words that have [startLetter] at letter [position] (1 = the
  /// first letter; a Daily variant links on the 2nd or 3rd) and are not in
  /// [exclude] (the words already played in the current chain).
  List<String> suggestWords(
    String startLetter, {
    Set<String> exclude = const {},
    int position = 1,
  }) {
    final letter = startLetter.trim();
    if (letter.isEmpty) return const [];
    final candidates = _words.where(
      (w) =>
          (position <= 1
              ? w.startsWith(letter)
              : letterAt(w, position) == letter) &&
          w.length >= _minLength &&
          !exclude.contains(w),
    );
    final preferred =
        candidates
            .where((w) => w.length >= _hintPreferredLength)
            .take(20)
            .toList();
    return preferred.isNotEmpty ? preferred : candidates.take(20).toList();
  }

  /// The [position]-th letter of [word] (1-based), not counting the
  /// half-space (ZWNJ), or null when the word is shorter. Daily variants link
  /// words on this letter. Mirrors Go `engine.LetterAt`.
  static String? letterAt(String word, int position) {
    if (position < 1) return null;
    final cleaned = word.trim().replaceAll(_zwnj, '');
    return position <= cleaned.length ? cleaned[position - 1] : null;
  }

  /// The index in [word] (code units, ZWNJ included) of its [position]-th
  /// letter, or null when the word is shorter — for highlighting it.
  static int? letterIndex(String word, int position) {
    var n = 0;
    for (var i = 0; i < word.length; i++) {
      if (word[i] == _zwnj) continue;
      n++;
      if (n == position) return i;
    }
    return null;
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
