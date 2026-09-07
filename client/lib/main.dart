import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/router/app_router.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/theme_cubit.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load dictionary before runApp so isValid() is ready immediately
  final dictionaryService = DictionaryService();
  await dictionaryService.load();

  // Wire DI
  await configureDependencies(dictionaryService);

  // Resolve auth state (AuthGuest or AuthAuthenticated) before building the
  // router so redirect never sees AuthInitial/AuthLoading on first evaluation.
  await getIt<AuthCubit>().init();

  // Build router after DI + auth are fully ready
  getIt.registerSingleton<GoRouter>(buildAppRouter());

  // Firebase — graceful fail without google-services config
  try {
    await Firebase.initializeApp();
    await GetIt.instance<NotificationService>().init();
  } catch (e) {
    Logger().w('Firebase init skipped: $e');
  }

  runApp(const WordChainApp());
}

class WordChainApp extends StatefulWidget {
  const WordChainApp({super.key});

  @override
  State<WordChainApp> createState() => _WordChainAppState();
}

class _WordChainAppState extends State<WordChainApp> {
  @override
  void initState() {
    super.initState();
    // Listen to FCM notification payloads and deep-link into the app.
    GetIt.instance<NotificationService>().payloadStream.listen((route) {
      if (route != null && route.isNotEmpty) {
        GetIt.instance<GoRouter>().go(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      bloc: getIt<ThemeCubit>(),
      builder: (context, themeMode) {
        return MaterialApp.router(
          title: 'WordChain',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          routerConfig: getIt<GoRouter>(),
          debugShowCheckedModeBanner: false,
          // Persian is RTL; the widget tree itself is not yet audited for
          // RTL layout screen-by-screen (see REDESIGN_PLAN.md Stage 1), but
          // the app-wide reading direction must be correct regardless.
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
    );
  }
}
