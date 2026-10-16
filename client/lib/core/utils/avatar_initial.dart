/// One-letter label for a player's avatar disc: the first character of
/// [name] when it is a letter, otherwise [fallback] («ت» from «تو»).
String avatarInitial(String? name, {String fallback = 'ت'}) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return fallback;
  final first = String.fromCharCode(trimmed.runes.first);
  return RegExp(r'^\p{L}$', unicode: true).hasMatch(first)
      ? first.toUpperCase()
      : fallback;
}
