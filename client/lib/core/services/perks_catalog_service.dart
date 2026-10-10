import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/network/dio_client.dart';

/// Image URL of a premium avatar. Served (and cached) by the backend, so no
/// artwork is bundled in the app.
String avatarImageUrl(String id) =>
    '${DioClient.baseUrl}${ApiEndpoints.avatarImage(id)}';

class PerkTaunt {
  final String id;
  final String text;

  const PerkTaunt({required this.id, required this.text});
}

/// Premium taunts and avatars as the server currently offers them, in picker
/// order. The server owns the catalogue; the client only ever sends an id.
class PerksCatalog {
  final List<PerkTaunt> taunts;
  final List<String> avatarIds;

  const PerksCatalog({this.taunts = const [], this.avatarIds = const []});

  static const empty = PerksCatalog();

  bool get isEmpty => taunts.isEmpty && avatarIds.isEmpty;

  factory PerksCatalog.fromJson(Map<String, dynamic> json) {
    final taunts = <PerkTaunt>[];
    for (final t in (json['taunts'] as List<dynamic>?) ?? const []) {
      final m = t as Map<String, dynamic>;
      final id = m['id'] as String? ?? '';
      final text = m['text'] as String? ?? '';
      if (id.isNotEmpty && text.isNotEmpty) {
        taunts.add(PerkTaunt(id: id, text: text));
      }
    }
    final avatars = <String>[];
    for (final a in (json['avatars'] as List<dynamic>?) ?? const []) {
      final id = (a as Map<String, dynamic>)['id'] as String? ?? '';
      if (id.isNotEmpty) avatars.add(id);
    }
    return PerksCatalog(taunts: taunts, avatarIds: avatars);
  }
}

/// Fetches the perks catalogue and keeps the last good copy in
/// `shared_preferences`, so the pickers still work offline. Never throws.
class PerksCatalogService {
  static const _cacheKey = 'perks_catalog_v1';

  final Dio _dio;
  final SharedPreferences _prefs;
  PerksCatalog? _memory;

  PerksCatalogService({required Dio dio, required SharedPreferences prefs})
    : _dio = dio,
      _prefs = prefs;

  /// Last known catalogue (empty on a first run that has never been online).
  PerksCatalog get cached {
    final memory = _memory;
    if (memory != null) return memory;
    var parsed = PerksCatalog.empty;
    try {
      final raw = _prefs.getString(_cacheKey);
      if (raw != null) {
        parsed = PerksCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // A corrupt cache is the same as no cache.
    }
    return _memory = parsed;
  }

  /// Loads the current catalogue; on any failure returns [cached].
  Future<PerksCatalog> refresh() async {
    try {
      final response = await _dio.get(ApiEndpoints.perksCatalog);
      final data = response.data['data'] as Map<String, dynamic>;
      final fresh = PerksCatalog.fromJson(data);
      await _prefs.setString(_cacheKey, jsonEncode(data));
      return _memory = fresh;
    } catch (_) {
      return cached;
    }
  }
}
