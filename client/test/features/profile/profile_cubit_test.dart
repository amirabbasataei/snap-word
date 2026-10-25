import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/features/profile/cubit/profile_cubit.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

const _remote = ProfileStats(
  totalMatches: 40,
  wins: 0,
  bestScore: 0,
  bestMatchStreak: 0,
  dailyStreak: 3,
  longestDailyStreak: 5,
  longestWord: 'کتابخانه',
  coins: 0,
  level: 4,
  xpInLevel: 300,
  xpForNext: 400,
);

class _Repo extends Fake implements ProfileRepository {
  Object? statsError;
  Object? perksError;
  Object? avatarError;
  PremiumPerks perks = PremiumPerks.none;
  int statsCalls = 0;
  final avatars = <String>[];

  @override
  Future<ProfileStats> fetchStats() async {
    statsCalls++;
    if (statsError != null) throw statsError!;
    return _remote;
  }

  @override
  Future<List<PowerupItem>> fetchInventory() async => const [
    PowerupItem(type: 'hint', quantity: 2),
  ];

  @override
  Future<PremiumPerks> fetchPerks() async {
    if (perksError != null) throw perksError!;
    return perks;
  }

  @override
  Future<void> setAvatar(String avatarId) async {
    avatars.add(avatarId);
    if (avatarError != null) throw avatarError!;
  }
}

class _Stats extends Fake implements StatsDao {
  LocalPlayerStat? local;
  RemoteStats? merged;

  @override
  Future<LocalPlayerStat?> getStats() async => local;

  @override
  Future<void> mergeWithRemote(RemoteStats remote) async => merged = remote;
}

class _Powerups extends Fake implements PowerupCacheDao {
  List<RemotePowerup> cached = const [];

  @override
  Future<void> refreshFromRemote(List<RemotePowerup> powerups) async =>
      cached = powerups;
}

const _localRow = LocalPlayerStat(
  id: 1,
  totalMatches: 12,
  wins: 0,
  bestScore: 900,
  bestMatchStreak: 17,
  dailyStreak: 1,
  longestDailyStreak: 2,
  longestWord: 'سلام',
);

void main() {
  late _Repo repo;
  late _Stats stats;
  late _Powerups powerups;

  setUp(() {
    repo = _Repo();
    stats = _Stats();
    powerups = _Powerups();
  });

  ProfileCubit make({bool guest = false}) => ProfileCubit(
    repository: repo,
    statsDao: stats,
    powerupCacheDao: powerups,
    isGuest: guest,
  );

  group('load', () {
    test('a guest reads the local row and never calls the server', () async {
      stats.local = _localRow;
      final cubit = make(guest: true);
      await cubit.load();
      final s = cubit.state as ProfileLoaded;
      expect(s.isGuest, isTrue);
      expect(s.stats.totalMatches, 12);
      expect(s.stats.bestMatchStreak, 17);
      expect(s.stats.longestWord, 'سلام');
      expect(repo.statsCalls, 0);
    });

    test('a guest with no games has zeroes', () async {
      final cubit = make(guest: true);
      await cubit.load();
      final s = cubit.state as ProfileLoaded;
      expect(s.stats.totalMatches, 0);
      expect(s.stats.longestWord, isNull);
    });

    test('signed in: server counters, local best chain', () async {
      stats.local = _localRow;
      final cubit = make();
      await cubit.load();
      final s = cubit.state as ProfileLoaded;
      // The server never writes best_match_streak, so the merged row wins.
      expect(s.stats.bestMatchStreak, 17);
      expect(s.stats.totalMatches, 40);
      expect(s.stats.dailyStreak, 3);
      expect(s.stats.level, 4);
      expect(s.stats.xpInLevel, 300);
      expect(stats.merged?.totalMatches, 40);
      expect(powerups.cached.single.powerupType, 'hint');
    });

    test('emits Loading first, then the profile', () async {
      final cubit = make();
      final seen = <Type>[];
      final sub = cubit.stream.listen((s) => seen.add(s.runtimeType));
      await cubit.load();
      await Future<void>.delayed(Duration.zero);
      expect(seen, [ProfileLoading, ProfileLoaded]);
      await sub.cancel();
    });

    test('a failed first load is an error with the Persian reason', () async {
      repo.statsError = const ProfileException('بارگذاری پروفایل ناموفق بود');
      final cubit = make();
      await cubit.load();
      expect(cubit.state, const ProfileError('بارگذاری پروفایل ناموفق بود'));
    });

    test('an unexpected error falls back to the generic line', () async {
      repo.statsError = StateError('boom');
      final cubit = make();
      await cubit.load();
      expect((cubit.state as ProfileError).message, isNotEmpty);
    });

    test('a failed perks lookup leaves a free profile', () async {
      repo.perksError = const ProfileException('x');
      final cubit = make();
      await cubit.load();
      expect((cubit.state as ProfileLoaded).perks.isPremium, isFalse);
    });
  });

  group('silent reload', () {
    test('keeps the data on screen and emits no Loading', () async {
      final cubit = make();
      await cubit.load();
      final seen = <Type>[];
      final sub = cubit.stream.listen((s) => seen.add(s.runtimeType));
      await cubit.load(silent: true);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [ProfileLoaded]);
      await sub.cancel();
    });

    test('a failure leaves the loaded state untouched', () async {
      final cubit = make();
      await cubit.load();
      final before = cubit.state;
      repo.statsError = const ProfileException('x');
      await cubit.load(silent: true);
      expect(cubit.state, same(before));
    });

    test(
      'before anything loaded, a silent reload behaves like a load',
      () async {
        repo.statsError = const ProfileException('x');
        final cubit = make();
        await cubit.load(silent: true);
        expect(cubit.state, isA<ProfileError>());
      },
    );
  });

  group('setAvatar', () {
    test('success updates the perks in the loaded state', () async {
      repo.perks = PremiumPerks(
        isPremium: true,
        premiumUntil: DateTime.utc(2030),
        avatarId: 'fox',
      );
      final cubit = make();
      await cubit.load();
      expect(await cubit.setAvatar('owl'), isNull);
      final s = cubit.state as ProfileLoaded;
      expect(s.perks.avatarId, 'owl');
      expect(s.perks.isPremium, isTrue);
      expect(s.perks.premiumUntil, DateTime.utc(2030));
    });

    test('a refusal returns the message and changes nothing', () async {
      repo.avatarError = const ProfileException(
        'این امکان فقط برای اشتراک ویژه فعال است',
      );
      final cubit = make();
      await cubit.load();
      final before = cubit.state;
      expect(
        await cubit.setAvatar('owl'),
        'این امکان فقط برای اشتراک ویژه فعال است',
      );
      expect(cubit.state, before);
    });

    test('nothing is sent before the profile is loaded', () async {
      final cubit = make();
      expect(await cubit.setAvatar('owl'), isNull);
      expect(repo.avatars, isEmpty);
    });
  });

  test('ProfileLoaded notices a changed premium date', () {
    ProfileLoaded with_(DateTime until) => ProfileLoaded(
      stats: _remote,
      powerups: const [],
      isGuest: false,
      perks: PremiumPerks(isPremium: true, premiumUntil: until),
    );
    expect(with_(DateTime.utc(2030)), with_(DateTime.utc(2030)));
    expect(with_(DateTime.utc(2030)), isNot(with_(DateTime.utc(2031))));
  });
}
