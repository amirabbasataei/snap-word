import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/network/dio_client.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';

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
}
