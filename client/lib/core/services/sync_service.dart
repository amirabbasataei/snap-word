import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class SyncService {
  final SharedPreferences _prefs;
  final Dio _dio;
  final MatchDao _matchDao;
  final StatsDao _statsDao;
  final PowerupCacheDao _powerupCacheDao;
  final Logger _log = Logger();

  SyncService({
    required SharedPreferences prefs,
    required Dio dio,
    required MatchDao matchDao,
    required StatsDao statsDao,
    required PowerupCacheDao powerupCacheDao,
  })  : _prefs = prefs,
        _dio = dio,
        _matchDao = matchDao,
        _statsDao = statsDao,
        _powerupCacheDao = powerupCacheDao;

  bool get _isGuest => _prefs.getString('jwt_access_token') == null;

  Future<void> sync() async {
    if (_isGuest) return;
    await _uploadUnsyncedMatches();
    await _mergeStats();
    await _refreshPowerupCache();
  }

  Future<void> _uploadUnsyncedMatches() async {
    final matches = await _matchDao.getUnsyncedMatches();
    for (final match in matches) {
      // An active match is still resumable locally — upload it once it ends.
      if (match.status == 'active' || match.endedAt == null) continue;
      try {
        final response = await _dio.post(
          ApiEndpoints.soloGame,
          data: {
            'mode': match.mode,
            'score': match.score,
            // Stored as a JSON string in Drift; the API expects an array.
            'word_chain': (jsonDecode(match.wordChain) as List<dynamic>).cast<String>(),
            'started_at': _toRfc3339(match.startedAt),
            'ended_at': _toRfc3339(match.endedAt!),
          },
        );
        final remoteId = response.data['data']['id'] as String;
        await _matchDao.markSynced(match.id, remoteId);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 409) {
          // Already exists server-side — mark synced silently
          final remoteId = e.response?.data['data']?['id'] as String? ?? '';
          await _matchDao.markSynced(match.id, remoteId);
        } else if (status != null && status >= 400 && status < 500) {
          // The server rejected this row; retrying won't help, and aborting
          // here would block every later match behind it. Skip it.
          _log.e('Match ${match.id} rejected by server ($status): ${e.response?.data}');
        } else {
          _log.w('Match sync failed, will retry: $e');
          return; // abort remaining; retry on next trigger
        }
      }
    }
  }

  Future<void> _mergeStats() async {
    try {
      final response = await _dio.get(ApiEndpoints.profileStats);
      final remote = RemoteStats.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      await _statsDao.mergeWithRemote(remote);
    } catch (e) {
      _log.w('Stats sync failed: $e');
    }
  }

  Future<void> _refreshPowerupCache() async {
    try {
      final response = await _dio.get(ApiEndpoints.powerupInventory);
      final list = (response.data['data']['items'] as List<dynamic>)
          .map((e) => RemotePowerup.fromJson(e as Map<String, dynamic>))
          .toList();
      await _powerupCacheDao.refreshFromRemote(list);
    } catch (e) {
      _log.w('Powerup cache refresh failed: $e');
    }
  }

  String _toRfc3339(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final min = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    return '$y-$m-${d}T$h:$min:${s}Z';
  }
}
