/// Premium perks catalogue. IDs mirror `config.TauntIDs` / `config.AvatarIDs`
/// in the Go backend (`test/core/utils/premium_catalog_test.dart` fails if they
/// drift). The server only ever relays an ID — the Persian text lives here.
abstract final class PremiumCatalog {
  /// Preset taunts, in picker order. Includes friendly ones on purpose.
  static const Map<String, String> taunts = {
    'what_happened': 'چی شد؟ نفست تموم شد؟',
    'hurry_up': 'زود باش!',
    'your_turn': 'نوبت توئه، بجنب!',
    'thinking': 'داری فکر می‌کنی یا خوابیدی؟',
    'too_easy': 'این که خیلی راحت بود 😎',
    'lucky': 'شانس آوردی!',
    'nice_one': 'آفرین، کلمهٔ خوبی بود 👏',
    'good_game': 'بازی خوبی بود 🤝',
    'oops': 'ای وای! 😅',
  };

  /// Premium avatar IDs, in picker order. Art is `assets/avatars/<id>.png`
  /// (DiceBear "Lorelei" by Lisa Wischofsky, CC0 1.0). The IDs are opaque keys
  /// stored server-side, so the art can be swapped without a migration.
  static const List<String> avatarIds = [
    'lion',
    'simorgh',
    'falcon',
    'fox',
    'owl',
    'cat',
    'horse',
    'dragon',
    'crown',
    'pen',
    'flame',
    'moon',
    'star',
    'diamond',
    'bolt',
    'rose',
  ];

  static String? tauntText(String id) => taunts[id];

  static bool hasAvatar(String? id) => id != null && avatarIds.contains(id);

  static String avatarAsset(String id) => 'assets/avatars/$id.png';

  /// Stable position of [id] in the catalogue, used to pick the tile accent.
  static int avatarIndex(String id) =>
      avatarIds.indexOf(id).clamp(0, avatarIds.length);
}
