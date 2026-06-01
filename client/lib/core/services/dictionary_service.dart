import 'dart:collection';

import 'package:flutter/services.dart';

class DictionaryService {
  static const _assetPath = 'assets/words/enable.txt';
  static const _minLength = 3;

  late final HashSet<String> _words;

  Future<void> load() async {
    final raw = await rootBundle.loadString(_assetPath);
    _words = HashSet<String>.from(
      raw.split('\n').map((w) => w.trim().toLowerCase()).where((w) => w.isNotEmpty),
    );
  }

  bool isValid(String word) {
    final normalized = word.trim().toLowerCase();
    if (normalized.length < _minLength) return false;
    if (!RegExp(r'^[a-z]+$').hasMatch(normalized)) return false;
    return _words.contains(normalized);
  }

  List<String> suggestWords(String startLetter) {
    final letter = startLetter.trim().toLowerCase();
    if (letter.isEmpty) return const [];
    return _words
        .where((w) => w.startsWith(letter) && w.length >= _minLength)
        .take(5)
        .toList();
  }
}
