import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/auth/view/widgets/edit_username_dialog.dart';
import 'package:wordchain/features/auth/view/widgets/referral_dialog.dart';

import '../../helpers/z_test_app.dart';

/// Canvas `ZDialogs` (Zanjir turn 14): 14a invite code, 14b username. The
/// frames are 396×812 at 1× so they can be laid next to the canvas render.
class _Auth extends Fake implements AuthCubit {
  AuthState _state = const AuthAuthenticated(
    userId: 'u1',
    username: 'wordplayer',
    coins: 100,
  );
  Object? redeemError;

  @override
  AuthState get state => _state;

  @override
  Future<void> updateUsername(String username) async {
    _state = (_state as AuthAuthenticated).copyWith(username: username);
  }

  @override
  Future<int> redeemReferral(String code) async {
    if (redeemError != null) throw redeemError!;
    return 50;
  }
}

class _Backdrop extends StatelessWidget {
  final Widget child;
  const _Backdrop({required this.child});

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [zs.sky1, zs.sky2, zs.sky3],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// The mascot loops and the caret blinks, so `pumpAndSettle` never returns.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadVazirmatn);

  late _Auth auth;
  setUp(() async {
    auth = _Auth();
    await GetIt.I.reset();
    GetIt.I.registerSingleton<AuthCubit>(auth);
  });
  tearDown(() => GetIt.I.reset());

  Future<void> open(
    WidgetTester tester,
    Brightness brightness,
    Future<Object?> Function(BuildContext) show,
  ) async {
    tester.view.physicalSize = const Size(396, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      zTestApp(
        _Backdrop(
          child: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
        brightness: brightness,
        reduceMotion: true,
      ),
    );
    show(ctx);
    await settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/z_dialogs_$name.png'),
  );

  testWidgets('14aL invite code — empty, light', (tester) async {
    await open(tester, Brightness.light, showReferralDialog);
    await shot(tester, '14aL');
  });

  testWidgets('14bL username — unchanged, light', (tester) async {
    await open(tester, Brightness.light, showEditUsernameDialog);
    await shot(tester, '14bL');
  });

  testWidgets('14aD invite code — refused code, dark', (tester) async {
    auth.redeemError = const AuthException(
      code: 'referral_not_found',
      message: 'x',
    );
    await open(tester, Brightness.dark, showReferralDialog);
    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.pump();
    await tester.tap(find.text('ثبت کد'));
    await settle(tester);
    await shot(tester, '14aD');
  });

  testWidgets('14bD username — saved, dark', (tester) async {
    await open(tester, Brightness.dark, showEditUsernameDialog);
    await tester.enterText(find.byType(TextField), 'chain_master');
    await tester.pump();
    await tester.tap(find.text('ذخیره'));
    await settle(tester);
    await shot(tester, '14bD');
  });
}
