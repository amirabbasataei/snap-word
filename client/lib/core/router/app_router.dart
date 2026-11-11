import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/audio_service.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/z_bottom_nav.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/view/z_login_screen.dart';
import 'package:wordchain/features/auth/view/z_otp_verify_screen.dart';
import 'package:wordchain/features/daily/view/daily_screen.dart';
import 'package:wordchain/features/daily/view/daily_board_screen.dart';
import 'package:wordchain/features/friends/view/z_friends_screen.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';
import 'package:wordchain/features/messages/view/messages_screen.dart';
import 'package:wordchain/features/rewards/view/rewards_screen.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/home/view/home_screen.dart';
import 'package:wordchain/features/leaderboard/view/z_board_screen.dart';
import 'package:wordchain/features/lobby/view/lobby_screen.dart';
import 'package:wordchain/features/profile/view/z_profile_screen.dart';
import 'package:wordchain/features/splash/view/splash_screen.dart';

/// Notifies GoRouter when the auth *kind* changes (the only thing the redirect
/// reads). Refreshing on every emit (e.g. a coin-balance update) would rebuild
/// the current route and drop its `extra` (GameRouteArgs → null cast crash).
class _AuthStateNotifier extends ChangeNotifier {
  StreamSubscription<AuthState>? _sub;

  _AuthStateNotifier(AuthCubit cubit) {
    var wasAuthenticated = cubit.state is AuthAuthenticated;
    _sub = cubit.stream.listen((s) {
      final isAuthenticated = s is AuthAuthenticated;
      if (isAuthenticated == wasAuthenticated) return;
      wasAuthenticated = isAuthenticated;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Where a signed-in player on a login page goes: the page they were sent
/// to log in for (`/login?return=…`, or the OTP page's args), else Home.
/// Redirecting here — rather than leaving it to the OTP screen — means the
/// router lands on the right page at once instead of flashing Home first.
String _afterLogin(Uri uri, Object? extra) {
  final raw =
      extra is OtpVerifyArgs ? extra.returnPath : uri.queryParameters['return'];
  final safe =
      raw != null &&
      raw.startsWith('/') &&
      !raw.startsWith('//') &&
      !raw.startsWith('/login') &&
      !raw.startsWith('/register');
  return safe ? raw : '/home';
}

/// The Daily variant of a `variant=` query value: a known one, else classic.
@visibleForTesting
int dailyVariantFrom(String? raw) {
  final v = int.tryParse(raw ?? '');
  return v != null && GameConstants.dailyVariants.contains(v)
      ? v
      : GameConstants.dailyVariantClassic;
}

/// The router's single redirect rule (see [buildAppRouter]).
@visibleForTesting
String? authRedirect({
  required Uri uri,
  required Object? extra,
  required AuthState authState,
}) {
  final path = uri.toString();
  final onAuthScreen =
      path.startsWith('/login') || path.startsWith('/register');
  if (authState is AuthAuthenticated && onAuthScreen) {
    return _afterLogin(uri, extra);
  }

  // The OTP page cannot be rebuilt without its args (e.g. a restored route).
  if (uri.path == '/login/otp' && extra is! OtpVerifyArgs) return '/login';

  // Daily challenge requires authentication. A picked variant
  // (`/daily?variant=2`) survives the sign-in.
  if (path.startsWith('/daily') && authState is! AuthAuthenticated) {
    final variant = uri.queryParameters['variant'];
    return variant == null
        ? '/login?return=/daily'
        : '/login?return=${Uri.encodeComponent('/daily?variant=$variant')}';
  }

  return null;
}

/// The root navigator's key — lets code above the router (e.g. foreground
/// push handling in `main.dart`) reach the root overlay for a `ZToast`.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Called from main() after DI + AuthCubit.init() are complete.
GoRouter buildAppRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: _AuthStateNotifier(getIt<AuthCubit>()),
    redirect:
        (context, state) => authRedirect(
          uri: state.uri,
          extra: state.extra,
          authState: getIt<AuthCubit>().state,
        ),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
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
                builder: (context, state) => const ZBoardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/friends',
                builder: (context, state) => const ZFriendsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ZProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/daily/board',
        builder:
            (context, state) => DailyBoardScreen(
              variant: dailyVariantFrom(state.uri.queryParameters['variant']),
            ),
      ),
      GoRoute(
        path: '/messages',
        builder: (context, state) => const MessagesScreen(),
      ),
      GoRoute(
        path: '/rewards',
        builder: (context, state) => const RewardsScreen(),
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
      GoRoute(path: '/lobby', builder: (context, state) => const LobbyScreen()),
      GoRoute(
        path: '/daily',
        builder:
            (context, state) => DailyScreen(
              variant: dailyVariantFrom(state.uri.queryParameters['variant']),
            ),
      ),
    ],
  );
}

class _MainShell extends StatefulWidget {
  final StatefulNavigationShell shell;

  const _MainShell({required this.shell});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    // The four tabs share one calm loop; a match swaps it for its own.
    Sfx.music(MusicTrack.menu);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.z.paper,
      // Home paints its own sky scene to the screen edge, so the floating
      // dock sits over it (HomeView pads for the dock via MediaQuery). The
      // other tabs end above the dock.
      extendBody: shell.currentIndex == MainTab.home,
      body: shell,
      bottomNavigationBar: BlocBuilder<MessagesCubit, MessagesState>(
        bloc: getIt<MessagesCubit>(),
        buildWhen: (a, b) => a.count != b.count,
        builder:
            (context, messages) => ZBottomNav(
              currentIndex: shell.currentIndex,
              friendsBadge: messages.count,
              onTap: (index) {
                Sfx.play(Sound.tab);
                shell.goBranch(
                  index,
                  initialLocation: index == shell.currentIndex,
                );
                getIt<TabRefreshBus>().notify(index);
              },
            ),
      ),
    );
  }
}
