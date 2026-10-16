/// First character of [name] (trimmed, upper-cased), or [fallback] when the
/// name is empty. Used by every avatar that shows an initial.
String nameInitial(String? name, {String fallback = '؟'}) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return fallback;
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// Like [nameInitial], but only a letter counts: a name starting with a digit
/// or symbol gets [fallback] («ت» from «تو») — the game-screen discs.
String avatarInitial(String? name, {String fallback = 'ت'}) {
  final initial = nameInitial(name, fallback: fallback);
  return RegExp(r'^\p{L}$', unicode: true).hasMatch(initial)
      ? initial
      : fallback;
}
