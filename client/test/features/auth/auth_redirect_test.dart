import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/router/app_router.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';

import 'auth_fakes.dart';

const _in = AuthAuthenticated(userId: 'u', username: 'n', coins: 1);
const _guest = AuthGuest();

String? go(String uri, AuthState auth, {Object? extra}) =>
    authRedirect(uri: Uri.parse(uri), extra: extra, authState: auth);

void main() {
  group('signed-in player on a login page', () {
    test('?return= is where they land', () {
      expect(go('/login?return=/friends', _in), '/friends');
      expect(go('/login?return=/daily', _in), '/daily');
      expect(go('/login?return=/lobby', _in), '/lobby');
    });

    test('without a target they land on Home', () {
      expect(go('/login', _in), '/home');
      expect(go('/register', _in), '/home');
    });

    test('the OTP page takes the target from its args', () {
      expect(
        go('/login/otp', _in, extra: otpArgs(returnPath: '/leaderboard')),
        '/leaderboard',
      );
      expect(go('/login/otp', _in, extra: otpArgs()), '/home');
    });

    test('a target that is not an in-app path is ignored', () {
      for (final bad in [
        '//evil.example',
        'https://evil.example',
        '/login',
        '/login/otp',
        '/register',
        '',
      ]) {
        expect(
          go('/login/otp', _in, extra: otpArgs(returnPath: bad)),
          '/home',
          reason: 'return=$bad',
        );
      }
    });
  });

  group('guest', () {
    test('can open the login pages', () {
      expect(go('/login', _guest), isNull);
      expect(go('/login?return=/friends', _guest), isNull);
      expect(go('/login/otp', _guest, extra: otpArgs()), isNull);
    });

    test('the OTP page without args goes back to the phone page', () {
      expect(go('/login/otp', _guest), '/login');
      expect(go('/login/otp', _guest, extra: 'junk'), '/login');
    });

    test('the daily challenge sends a guest to log in first', () {
      expect(go('/daily', _guest), '/login?return=/daily');
      expect(go('/daily/board', _guest), '/login?return=/daily');
      expect(go('/daily', const AuthInitial()), '/login?return=/daily');
    });

    test('solo, lobby and tabs are open to guests', () {
      for (final p in [
        '/home',
        '/friends',
        '/leaderboard',
        '/lobby',
        '/game',
      ]) {
        expect(go(p, _guest), isNull, reason: p);
      }
    });
  });

  test('a signed-in player can open everything else', () {
    for (final p in ['/home', '/daily', '/friends', '/profile']) {
      expect(go(p, _in), isNull, reason: p);
    }
  });
}
