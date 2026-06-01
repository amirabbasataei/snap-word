import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/view/login_screen.dart';
import 'package:wordchain/features/auth/view/register_screen.dart';
import 'package:wordchain/features/daily/view/daily_screen.dart';
import 'package:wordchain/features/friends/view/friends_screen.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/tutorial_screen.dart';
import 'package:wordchain/features/home/view/home_screen.dart';
import 'package:wordchain/features/leaderboard/view/leaderboard_screen.dart';
import 'package:wordchain/features/lobby/view/lobby_screen.dart';
import 'package:wordchain/features/profile/view/profile_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  redirect: (context, state) {
    final prefs = getIt<SharedPreferences>();
    final tutorialDone = prefs.getBool('tutorial_completed') ?? false;
    final onTutorial = state.uri.toString().startsWith('/tutorial');
    if (!tutorialDone && !onTutorial) return '/tutorial';
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
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
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

class _MainShell extends StatelessWidget {
  final StatefulNavigationShell shell;

  const _MainShell({required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: shell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: shell.currentIndex,
          onTap: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events_outlined),
              activeIcon: Icon(Icons.emoji_events),
              label: 'Ranks',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Friends',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
