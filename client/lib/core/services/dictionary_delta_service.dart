import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/services/dictionary_service.dart';

/// Keeps the bundled word list current without an app release: the server's
/// admin-approved additions, removals and AI blocks (`GET /dictionary/delta`)
/// are applied over `fa.txt` at startup from the last good copy, then
/// refreshed in the background. It never throws and never gates the first
/// frame — offline, the player simply plays on the last delta they have.
class DictionaryDeltaService with WidgetsBindingObserver {
  static const cacheKey = 'dictionary_delta_v1';

  /// A page is capped by the server (`more`); this bounds a runaway loop.
  static const _maxPages = 20;

  /// App resumes refresh at most this often (a manual [refresh] can force it).
  static const minRefreshGap = Duration(minutes: 10);

  static final _log = Logger();

  final Dio _dio;
  final SharedPreferences _prefs;
  final DictionaryService _dictionary;
  final DateTime Function() _now;

  int _seq = 0;
  final Map<String, DictionaryChange> _changes = {};
  DateTime? _lastRefresh;
  bool _refreshing = false;

  DictionaryDeltaService({
    required Dio dio,
    required SharedPreferences prefs,
    required DictionaryService dictionary,
    DateTime Function()? now,
  }) : _dio = dio,
       _prefs = prefs,
       _dictionary = dictionary,
       _now = now ?? DateTime.now;

  /// Applies the cached delta now, refreshes in the background, and refreshes
  /// again whenever the app returns to the foreground.
  void start() {
    applyCached();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh(force: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  /// The server sequence number this device has caught up to.
  int get seq => _seq;

  /// Applies the cached delta to the loaded dictionary (synchronous, small).
  void applyCached() {
    try {
      final raw = _prefs.getString(cacheKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final changes = _parseChanges(json['changes']);
      _seq = (json['seq'] as num?)?.toInt() ?? 0;
      for (final c in changes) {
        _changes[c.word] = c;
      }
      _dictionary.applyChanges(_changes.values);
    } catch (e) {
      // A corrupt cache is the same as none: start again from seq 0.
      _log.w('dictionary delta cache ignored: $e');
      _seq = 0;
      _changes.clear();
    }
  }

  /// Fetches everything newer than [seq] and applies it. Skipped when a
  /// refresh ran less than [minRefreshGap] ago unless [force].
  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return;
    final last = _lastRefresh;
    if (!force && last != null && _now().difference(last) < minRefreshGap) {
      return;
    }
    _refreshing = true;
    try {
      for (var page = 0; page < _maxPages; page++) {
        final response = await _dio.get(
          ApiEndpoints.dictionaryDelta,
          queryParameters: {'since': _seq},
        );
        final data = response.data['data'] as Map<String, dynamic>;
        if (data['reset'] == true) {
          // The server's database is behind this device (a restore): what was
          // cached no longer applies. Words already applied this run stay
          // until the next start.
          _changes.clear();
        }
        final changes = _parseChanges(data['changes']);
        _dictionary.applyChanges(changes);
        for (final c in changes) {
          _changes[c.word] = c;
        }
        _seq = (data['seq'] as num?)?.toInt() ?? _seq;
        await _persist();
        if (data['more'] != true) break;
      }
      _lastRefresh = _now();
    } catch (e) {
      // Offline or a server hiccup: keep what we have, try again later.
      _log.d('dictionary delta refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _persist() => _prefs.setString(
    cacheKey,
    jsonEncode({
      'seq': _seq,
      'changes': [
        for (final c in _changes.values)
          {'w': c.word, 'p': c.present, 'a': c.aiBlocked},
      ],
    }),
  );

  /// Accepts both the wire shape (`word/present/ai_blocked`) and the cache
  /// shape (`w/p/a`); anything malformed is skipped.
  static List<DictionaryChange> _parseChanges(Object? raw) {
    final out = <DictionaryChange>[];
    for (final item in (raw as List<dynamic>?) ?? const []) {
      if (item is! Map<String, dynamic>) continue;
      final word = (item['word'] ?? item['w']) as String?;
      if (word == null || word.isEmpty) continue;
      out.add(
        DictionaryChange(
          word: word,
          present: (item['present'] ?? item['p']) as bool? ?? true,
          aiBlocked: (item['ai_blocked'] ?? item['a']) as bool? ?? false,
        ),
      );
    }
    return out;
  }
}
