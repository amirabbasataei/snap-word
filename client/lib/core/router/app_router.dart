import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/widgets/z_bottom_nav.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/view/z_login_screen.dart';
import 'package:wordchain/features/auth/view/z_otp_verify_screen.dart';
import 'package:wordchain/features/daily/view/daily_screen.dart';
import 'package:wordchain/features/friends/view/friends_screen.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/tutorial_screen.dart';
import 'package:wordchain/features/home/view/home_screen.dart';
import 'package:wordchain/features/leaderboard/view/leaderboard_screen.dart';
import 'package:wordchain/features/lobby/view/lobby_screen.dart';
import 'package:wordchain/features/profile/view/profile_screen.dart';

/// Notifies GoRouter whenever AuthCubit emits a new state.
class _AuthStateNotifier extends ChangeNotifier {
  StreamSubscription<AuthState>? _sub;

  _AuthStateNotifier(AuthCubit cubit) {
    _sub = cubit.stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Called from main() after DI + AuthCubit.init() are complete.
GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _AuthStateNotifier(getIt<AuthCubit>()),
    redirect: (context, state) {
      final prefs = getIt<SharedPreferences>();
      final tutorialDone = prefs.getBool('tutorial_completed') ?? false;
      final path = state.uri.toString();
      final onTutorial = path.startsWith('/tutorial');
      if (!tutorialDone && !onTutorial) return '/tutorial';

      final authState = getIt<AuthCubit>().state;
      final onAuthScreen =
          path.startsWith('/login') || path.startsWith('/register');
      if (authState is AuthAuthenticated && onAuthScreen) return '/home';

      // Daily challenge requires authentication
      if (path.startsWith('/daily') && authState is! AuthAuthenticated) {
        return '/login?return=/daily';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/tutorial',
        builder: (context, state) => const TutorialScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/leaderboard',
                builder: (context, state) => const LeaderboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/friends',
                builder: (context, state) => const FriendsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final returnPath = state.uri.queryParameters['return'];
          return ZLoginScreen(returnPath: returnPath);
        },
      ),
      GoRoute(
        path: '/login/otp',
        builder: (context, state) {
          final args = state.extra as OtpVerifyArgs;
          return ZOtpVerifyScreen(args: args);
        },
      ),
      GoRoute(
        path: '/game',
        builder: (context, state) {
          final args = state.extra as GameRouteArgs;
          return GameScreen(args: args);
        },
      ),
      GoRoute(
        path: '/lobby',
        builder: (context, state) => const LobbyScreen(),
      ),
      GoRoute(
        path: '/daily',
        builder: (context, state) => const DailyScreen(),
      ),
    ],
  );
}

class _MainShell extends StatelessWidget {
  final StatefulNavigationShell shell;

  const _MainShell({required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: shell,
      bottomNavigationBar: ZBottomNav(
        currentIndex: shell.currentIndex,
        onTap: (index) => shell.goBranch(
          index,
          initialLocation: index == shell.currentIndex,
        ),
      ),
    );
  }
}
