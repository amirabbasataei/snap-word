import 'dart:math';

import 'package:wordchain/core/services/dictionary_service.dart';

/// The Persian letters the fewest fa.txt words start with (ژ ظ ث ذ ض).
/// Ending a word on one leaves the opponent few follow-ups. ی is excluded:
/// few words start with it but ~2.6k end with it. Keep in sync with Go's
/// `config.AITrapLetters`.
const aiTrapLetters = {'ژ', 'ظ', 'ث', 'ذ', 'ض'};

class AIDifficultyConfig {
  final int delayMs;
  final double mistakeRate;
  final int minWordLength;
  final double trapPref;
  final bool preferLongest;

  const AIDifficultyConfig({
    required this.delayMs,
    required this.mistakeRate,
    required this.minWordLength,
    required this.trapPref,
    required this.preferLongest,
  });
}

const aiDifficulties = <String, AIDifficultyConfig>{
  'easy': AIDifficultyConfig(
    delayMs: 3000,
    mistakeRate: 0.25,
    minWordLength: 3,
    trapPref: 0,
    preferLongest: false,
  ),
  'medium': AIDifficultyConfig(
    delayMs: 1500,
    mistakeRate: 0.10,
    minWordLength: 4,
    trapPref: 0.30,
    preferLongest: false,
  ),
  'hard': AIDifficultyConfig(
    delayMs: 600,
    mistakeRate: 0.02,
    minWordLength: 6,
    trapPref: 0.70,
    preferLongest: true,
  ),
};

String? selectAIWord({
  required String? letter,
  required Set<String> usedWords,
  required DictionaryService dictionary,
  required AIDifficultyConfig difficulty,
}) {
  final rng = Random();
  final candidates = <String>[];
  final trapCandidates = <String>[];

  for (final w in dictionary.words) {
    if (w.length < difficulty.minWordLength) continue;
    if (letter != null && letter.isNotEmpty && w[0] != letter) continue;
    if (usedWords.contains(w)) continue;
    candidates.add(w);
    if (aiTrapLetters.contains(DictionaryService.lastLetterOf(w))) {
      trapCandidates.add(w);
    }
  }

  if (trapCandidates.isNotEmpty &&
      difficulty.trapPref > 0 &&
      rng.nextDouble() < difficulty.trapPref) {
    if (difficulty.preferLongest) {
      trapCandidates.sort((a, b) => b.length.compareTo(a.length));
      return trapCandidates.first;
    }
    return trapCandidates[rng.nextInt(trapCandidates.length)];
  }

  if (candidates.isEmpty) return null;
  return candidates[rng.nextInt(candidates.length)];
}

String resolveAIDifficulty(String opponentType) {
  return opponentType.startsWith('ai_') ? opponentType.substring(3) : 'easy';
}

bool isVsAI(String opponentType) => opponentType.startsWith('ai_');

/// The player's longest word in a finished chain, ignoring the opponent's.
/// vs-AI games always open with the player and strictly alternate, so the
/// player owns the even indices; solo chains are entirely theirs.
String? longestOwnWord(List<String> chain, String? opponentType) {
  String? longest;
  for (var i = 0; i < chain.length; i++) {
    if (opponentType != null && isVsAI(opponentType) && i.isOdd) continue;
    if (longest == null || chain[i].length > longest.length) longest = chain[i];
  }
  return longest;
}
