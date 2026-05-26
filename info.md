question:
Why did you say the dictionary should be on the backend? I think the dictionary can be inside the Flutter app itself. In this case, there is no need to call the API and the speed increases dramatically.

claude answer:
You're making a valid point, and you're **partially right** — but there's an important nuance that depends on the game mode.

## Where you're right

For solo and vs-AI games, putting the dictionary in the Flutter app is strictly better:

- Validation is instant (0ms vs 100–300ms round-trip)
- Works offline
- Zero server load per word submission
- Better UX — you can even validate letter-by-letter as the user types

The ENABLE wordlist is ~1.7 MB as plain text, or roughly ~500 KB gzipped. That's perfectly fine to bundle as a Flutter asset. You load it into a `HashSet<String>` at app startup and lookups are O(1).

## Where the backend still needs it

For **multiplayer**, you can't remove server-side validation. Here's why:

The client can be tampered with. A cheater can modify their Flutter app to make the local dictionary accept any string. If the server trusts the client's word submissions without checking, the cheater wins every game. In competitive games, the server is always the **authority** — the client's validation is just a UX convenience.

## The right hybrid architecture

```
Solo / vs AI
  User types → Client validates instantly → Accept or reject
  (server never involved in word validation)

Multiplayer
  User types → Client validates instantly → Show green border (optimistic)
               → Also sends word to server → Server re-validates
               → If server rejects → client corrects (rare, only for cheaters)
               → Both players see server's authoritative result
```

This pattern is called **optimistic validation** — the client gives instant feedback while the server has the final say.

## What changes in CLAUDE.md

You should update Phase 2 and Phase 8 to reflect this:

**Phase 2 (backend engine):** Keep `IsValid()` in Go — it's still needed for multiplayer rooms. But it's no longer in the hot path for solo games.

**Phase 8 (Flutter core):** Add dictionary loading to the app startup. Something like:

```dart
// core/services/dictionary_service.dart
class DictionaryService {
  late final HashSet<String> _words;

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/words/enable.txt');
    _words = HashSet.from(raw.split('\n').map((w) => w.trim().toLowerCase()));
  }

  bool isValid(String word) => _words.contains(word.toLowerCase());

  // Bonus: suggest words starting with a letter (for hint power-up)
  List<String> suggestWords(String startLetter, {int limit = 5}) {
    return _words
        .where((w) => w.startsWith(startLetter.toLowerCase()) && w.length >= 4)
        .take(limit)
        .toList();
  }
}
```

Register it in `get_it`, call `load()` in `main()` before `runApp()`, and inject it into `GameBloc`. This also makes the **Hint power-up** completely free — no server call needed, just `suggestWords('e')` locally.

Good catch — this is a real architectural improvement worth making.