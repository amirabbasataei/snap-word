import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

part 'profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final ProfileRepository _repo;
  final StatsDao _statsDao;
  final PowerupCacheDao _powerupCacheDao;
  final bool isGuest;

  ProfileCubit({
    required ProfileRepository repository,
    required StatsDao statsDao,
    required PowerupCacheDao powerupCacheDao,
    required this.isGuest,
  })  : _repo = repository,
        _statsDao = statsDao,
        _powerupCacheDao = powerupCacheDao,
        super(const ProfileInitial());

  Future<void> load() async {
    emit(const ProfileLoading());
    try {
      if (isGuest) {
        await _loadGuest();
      } else {
        await _loadAuthenticated();
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _loadGuest() async {
    final local = await _statsDao.getStats();
    emit(ProfileLoaded(
      stats: ProfileStats(
        totalMatches: local?.totalMatches ?? 0,
        wins: local?.wins ?? 0,
        bestScore: local?.bestScore ?? 0,
        bestMatchStreak: local?.bestMatchStreak ?? 0,
        dailyStreak: local?.dailyStreak ?? 0,
        longestDailyStreak: local?.longestDailyStreak ?? 0,
        longestWord: local?.longestWord,
        coins: 0,
      ),
      powerups: const [],
      isGuest: true,
    ));
  }

  Future<void> _loadAuthenticated() async {
    final results = await Future.wait([
      _repo.fetchStats(),
      _repo.fetchInventory(),
    ]);

    final remoteStats = results[0] as ProfileStats;
    final powerups = results[1] as List<PowerupItem>;

    // Update local cache with backend stats
    await _statsDao.mergeWithRemote(RemoteStats(
      totalMatches: remoteStats.totalMatches,
      wins: remoteStats.wins,
      bestScore: remoteStats.bestScore,
      bestMatchStreak: remoteStats.bestMatchStreak,
      dailyStreak: remoteStats.dailyStreak,
      longestDailyStreak: remoteStats.longestDailyStreak,
      longestWord: remoteStats.longestWord,
    ));

    // Update powerup cache
    await _powerupCacheDao.refreshFromRemote(
      powerups
          .map((p) =>
              RemotePowerup(powerupType: p.type, quantity: p.quantity))
          .toList(),
    );

    // The server never writes bestScore/bestMatchStreak (no call site
    // upserts those columns — see ZProfile Stage 5 backend audit), so
    // showing remoteStats directly would silently discard real solo/AI
    // progress that only exists locally. Re-read the just-merged (max of
    // local/remote) row instead — dailyStreak/totalMatches/longestWord stay
    // server-authoritative since those ARE written server-side.
    final merged = await _statsDao.getStats();

    emit(ProfileLoaded(
      stats: ProfileStats(
        totalMatches: remoteStats.totalMatches,
        wins: remoteStats.wins,
        bestScore: merged?.bestScore ?? remoteStats.bestScore,
        bestMatchStreak: merged?.bestMatchStreak ?? remoteStats.bestMatchStreak,
        dailyStreak: remoteStats.dailyStreak,
        longestDailyStreak: remoteStats.longestDailyStreak,
        longestWord: remoteStats.longestWord,
        coins: remoteStats.coins,
      ),
      powerups: powerups,
      isGuest: false,
    ));
  }
}
