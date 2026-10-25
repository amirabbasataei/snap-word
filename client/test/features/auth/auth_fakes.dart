import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/router/app_router.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/auth/view/z_login_screen.dart';
import 'package:wordchain/features/auth/view/z_otp_verify_screen.dart';

const defaultSend = SendOtpResult(
  expiresInSeconds: 120,
  resendCooldownSeconds: 120,
);

/// An existing account's answer to verify-otp.
const signedIn = AuthResult(
  userId: 'u1',
  username: 'zanjir_1',
  coins: 340,
  isNewUser: false,
);

/// A new account's answer: the balance is the welcome gift.
AuthResult newcomer({int coins = 50, String? referralWarning}) => AuthResult(
  userId: 'u2',
  username: 'zanjir_2',
  coins: coins,
  isNewUser: true,
  referralWarning: referralWarning,
);

AuthException authError(String code) =>
    AuthException(code: code, message: 'server says $code');

/// Auth cubit stand-in: programmable send-otp / verify-otp answers (consumed
/// in order, the last one repeats), a state the router can listen to and a log
/// of what the screens asked for.
class FakeAuth extends Fake implements AuthCubit {
  AuthState _state = const AuthGuest();
  final _controller = StreamController<AuthState>.broadcast();

  /// Each entry is a [SendOtpResult] to return or an [Exception] to throw.
  final sendAnswers = <Object>[];
  final verifyAnswers = <Object>[];
  final sentTo = <String>[];
  final verifies = <({String phone, String code, String? referral})>[];
  int guestTaps = 0;

  /// While set, send-otp waits for it (a request in flight).
  Completer<SendOtpResult>? sendGate;

  /// While set, verify-otp waits for it.
  Completer<void>? verifyGate;

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => _controller.stream;

  @override
  bool get isGuest => _state is! AuthAuthenticated;

  void emitState(AuthState next) {
    _state = next;
    _controller.add(next);
  }

  @override
  Future<SendOtpResult> sendOtp({required String phone}) async {
    sentTo.add(phone);
    final gate = sendGate;
    if (gate != null) return gate.future;
    final a = sendAnswers.isEmpty ? defaultSend : _next(sendAnswers);
    if (a is Exception) throw a;
    return a as SendOtpResult;
  }

  @override
  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
    String? referralCode,
  }) async {
    verifies.add((phone: phone, code: code, referral: referralCode));
    await verifyGate?.future;
    final a = verifyAnswers.isEmpty ? signedIn : _next(verifyAnswers);
    if (a is Exception) throw a;
    final r = a as AuthResult;
    emitState(
      AuthAuthenticated(userId: r.userId, username: r.username, coins: r.coins),
    );
    return r;
  }

  @override
  void continueAsGuest() {
    guestTaps++;
    emitState(const AuthGuest());
  }

  Object _next(List<Object> l) => l.length > 1 ? l.removeAt(0) : l.first;

  Future<void> dispose() => _controller.close();
}

/// Mirrors the router's own refresh rule: re-evaluate when the auth *kind*
/// flips.
class _Refresh extends ChangeNotifier {
  _Refresh(FakeAuth auth) {
    var was = auth.state is AuthAuthenticated;
    auth.stream.listen((s) {
      final now = s is AuthAuthenticated;
      if (now == was) return;
      was = now;
      notifyListeners();
    });
  }
}

/// The two login screens inside a real GoRouter with the app's own redirect
/// rule, plus plain stand-ins for the pages a login can end on.
/// A clock the test moves by hand; [advance] also lets timers run.
class TestClock {
  var elapsed = Duration.zero;
  final start = DateTime(2026, 10, 25, 12);

  DateTime now() => start.add(elapsed);

  /// Moves the clock one second at a time, pumping after each, so the
  /// cubit's one-second ticker sees every step.
  Future<void> advance(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      elapsed += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

GoRouter loginRouter(
  FakeAuth auth, {
  TestClock? clock,
  String initial = '/login',
  Object? extra,
  List<String>? visited,
}) {
  Widget page(String name) => Scaffold(body: Center(child: Text('page:$name')));
  return GoRouter(
    initialLocation: initial,
    initialExtra: extra,
    refreshListenable: _Refresh(auth),
    redirect: (context, state) {
      final to = authRedirect(
        uri: state.uri,
        extra: state.extra,
        authState: auth.state,
      );
      visited?.add(to ?? state.uri.toString());
      return to;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder:
            (_, s) => ZLoginScreen(
              returnPath: s.uri.queryParameters['return'],
              clock: clock?.now,
            ),
      ),
      GoRoute(
        path: '/login/otp',
        builder:
            (_, s) => ZOtpVerifyScreen(
              args: s.extra as OtpVerifyArgs,
              clock: clock?.now,
            ),
      ),
      GoRoute(path: '/home', builder: (_, _) => page('home')),
      GoRoute(path: '/friends', builder: (_, _) => page('friends')),
      GoRoute(path: '/leaderboard', builder: (_, _) => page('board')),
      GoRoute(path: '/daily', builder: (_, _) => page('daily')),
    ],
  );
}

Widget loginApp(
  GoRouter router, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool reduceMotion = true,
}) {
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
    routerConfig: router,
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
  );
}

FakeAuth registerAuth() {
  final auth = FakeAuth();
  GetIt.I.registerSingleton<AuthCubit>(auth);
  return auth;
}

void unregisterAuth() => GetIt.I.reset();

OtpVerifyArgs otpArgs({
  String phone = '09364419970',
  String? returnPath,
  String? referral,
  int cooldown = 120,
  int? expires = 120,
}) => OtpVerifyArgs(
  phone: phone,
  returnPath: returnPath,
  referralCode: referral,
  initialCooldownSeconds: cooldown,
  initialExpiresSeconds: expires,
);
