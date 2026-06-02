import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/network/dio_client.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/lobby/data/lobby_repository.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies(DictionaryService dictionaryService) async {
  final prefs = await SharedPreferences.getInstance();

  // Primitives
  getIt.registerSingleton<SharedPreferences>(prefs);
  getIt.registerSingleton<DictionaryService>(dictionaryService);

  // Database
  getIt.registerLazySingleton<AppDatabase>(() => AppDatabase());

  // DAOs — resolved from the database instance via generated accessors
  getIt.registerLazySingleton<MatchDao>(() => getIt<AppDatabase>().matchDao);
  getIt.registerLazySingleton<UsedWordDao>(
    () => getIt<AppDatabase>().usedWordDao,
  );
  getIt.registerLazySingleton<StatsDao>(() => getIt<AppDatabase>().statsDao);
  getIt.registerLazySingleton<PowerupCacheDao>(
    () => getIt<AppDatabase>().powerupCacheDao,
  );

  // Network
  getIt.registerLazySingleton<DioClient>(
    () => DioClient(getIt<SharedPreferences>()),
  );

  // Services
  getIt.registerLazySingleton<WebSocketService>(() => WebSocketService());
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(getIt<DioClient>().dio),
  );
  getIt.registerLazySingleton<ShareService>(() => ShareService());
  getIt.registerLazySingleton<SyncService>(
    () => SyncService(
      prefs: getIt<SharedPreferences>(),
      dio: getIt<DioClient>().dio,
      matchDao: getIt<MatchDao>(),
      statsDao: getIt<StatsDao>(),
      powerupCacheDao: getIt<PowerupCacheDao>(),
    ),
  );

  // Auth
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      dio: getIt<DioClient>().dio,
      prefs: getIt<SharedPreferences>(),
    ),
  );
  getIt.registerLazySingleton<AuthCubit>(
    () => AuthCubit(
      authRepository: getIt<AuthRepository>(),
      syncService: getIt<SyncService>(),
    ),
  );

  // Game
  getIt.registerLazySingleton<GameRepository>(
    () => GameRepository(
      db: getIt<AppDatabase>(),
      matchDao: getIt<MatchDao>(),
      usedWordDao: getIt<UsedWordDao>(),
      dio: getIt<DioClient>().dio,
    ),
  );

  // Lobby
  getIt.registerLazySingleton<LobbyRepository>(
    () => LobbyRepository(dio: getIt<DioClient>().dio),
  );

  // Leaderboard
  getIt.registerLazySingleton<LeaderboardRepository>(
    () => LeaderboardRepository(dio: getIt<DioClient>().dio),
  );

  // Friends
  getIt.registerLazySingleton<FriendsRepository>(
    () => FriendsRepository(dio: getIt<DioClient>().dio),
  );

  // Profile
  getIt.registerLazySingleton<ProfileRepository>(
    () => ProfileRepository(dio: getIt<DioClient>().dio),
  );

  // Daily challenge
  getIt.registerLazySingleton<DailyRepository>(
    () => DailyRepository(dio: getIt<DioClient>().dio),
  );
}
