import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/router/app_router.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load dictionary before runApp so isValid() is ready immediately
  final dictionaryService = DictionaryService();
  await dictionaryService.load();

  // Wire DI
  await configureDependencies(dictionaryService);

  // Firebase — graceful fail without google-services config
  try {
    await Firebase.initializeApp();
    await GetIt.instance<NotificationService>().init();
  } catch (e) {
    Logger().w('Firebase init skipped: $e');
  }

  runApp(const WordChainApp());
}

class WordChainApp extends StatelessWidget {
  const WordChainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WordChain',
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
