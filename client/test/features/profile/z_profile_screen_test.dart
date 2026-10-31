import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/legal_links.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/services/perks_catalog_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/theme_cubit.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/avatar_tile.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';
import 'package:wordchain/features/profile/view/widgets/profile_header.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';
import 'package:wordchain/features/profile/view/z_profile_screen.dart';

import '../../helpers/contrast.dart';
import '../../helpers/z_test_app.dart';

final _lri = String.fromCharCode(0x2066);
final _pdi = String.fromCharCode(0x2069);

const _signedIn = AuthAuthenticated(
  userId: 'me-1',
  username: 'آرش',
  coins: 1240,
);

const _stats = ProfileStats(
  totalMatches: 87,
  wins: 0,
  bestScore: 4100,
  bestMatchStreak: 23,
  dailyStreak: 5,
  longestDailyStreak: 9,
  longestWord: 'می‌روم',
  coins: 0,
  level: 12,
  xpInLevel: 620,
  xpForNext: 1000,
);

/// Auth cubit stand-in that can emit and records what the screen asks of it.
class _Auth extends Fake implements AuthCubit {
  AuthState _state;
  final _controller = StreamController<AuthState>.broadcast();

  Object? codeError;
  String code = 'K7M2QX';
  int codeFetches = 0;
  Object? renameError;
  Object? redeemError;
  final renamed = <String>[];
  final redeemed = <String>[];
  int logouts = 0;

  _Auth(this._state);

  void emitState(AuthState next) {
    _state = next;
    _controller.add(next);
  }

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => _controller.stream;

  @override
  bool get isGuest => _state is! AuthAuthenticated;

  @override
  Future<String> fetchMyReferralCode() async {
    codeFetches++;
    if (codeError != null) throw codeError!;
    return code;
  }

  @override
  Future<void> updateUsername(String username) async {
    renamed.add(username);
    if (renameError != null) throw renameError!;
    final s = _state;
    if (s is AuthAuthenticated) emitState(s.copyWith(username: username));
  }

  @override
  Future<int> redeemReferral(String code) async {
    redeemed.add(code);
    if (redeemError != null) throw redeemError!;
    final s = _state;
    if (s is AuthAuthenticated) emitState(s.copyWith(coins: s.coins + 50));
    return 50;
  }

  @override
  Future<void> logout() async {
    logouts++;
    emitState(const AuthGuest());
  }

  @override
  Future<void> close() async => _controller.close();
}

class _FakeRepo extends Fake implements ProfileRepository {
  ProfileStats stats = _stats;
  PremiumPerks perks = PremiumPerks.none;
  Completer<ProfileStats>? statsGate;
  Object? statsError;
  Object? perksError;
  Object? avatarError;
  int statsFetches = 0;
  int inventoryFetches = 0;
  final avatarsSet = <String>[];

  @override
  Future<ProfileStats> fetchStats() async {
    statsFetches++;
    if (statsGate != null) return statsGate!.future;
    if (statsError != null) throw statsError!;
    return stats;
  }

  @override
  Future<List<PowerupItem>> fetchInventory() async {
    inventoryFetches++;
    return const [];
  }

  @override
  Future<PremiumPerks> fetchPerks() async {
    if (perksError != null) throw perksError!;
    return perks;
  }

  @override
  Future<void> setAvatar(String avatarId) async {
    avatarsSet.add(avatarId);
    if (avatarError != null) throw avatarError!;
  }
}

class _FakeStatsDao extends Fake implements StatsDao {
  LocalPlayerStat? local;
  final merged = <RemoteStats>[];

  @override
  Future<LocalPlayerStat?> getStats() async => local;

  @override
  Future<void> mergeWithRemote(RemoteStats remote) async {
    merged.add(remote);
  }
}

class _FakePowerups extends Fake implements PowerupCacheDao {
  @override
  Future<void> refreshFromRemote(List<RemotePowerup> powerups) async {}
}

class _FakeShare extends Fake implements ShareService {
  final codes = <String>[];

  @override
  Future<void> shareInvite({required String code}) async => codes.add(code);
}

class _FakeMoney extends Fake implements MonetizationService {
  PurchaseResult result = const PurchaseResult(status: PurchaseStatus.success);
  final bought = <String>[];

  @override
  Future<PurchaseResult> purchase(String productId) async {
    bought.add(productId);
    return result;
  }
}

class _FakeCatalog extends Fake implements PerksCatalogService {
  @override
  PerksCatalog get cached => const PerksCatalog(avatarIds: ['fox', 'owl']);

  @override
  Future<PerksCatalog> refresh() async => cached;
}

class _Harness {
  final repo = _FakeRepo();
  final dao = _FakeStatsDao();
  final share = _FakeShare();
  final money = _FakeMoney();
  final bus = TabRefreshBus();
  final routes = <String>[];
  late _Auth auth;
  late ThemeCubit theme;
  Object? codeError;
  String code = 'K7M2QX';
  final clipboard = <String>[];
  final openedLinks = <Uri>[];
  bool linksLaunch = true;

  Future<void> register({
    AuthState state = _signedIn,
    ThemeMode mode = ThemeMode.light,
  }) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': mode == ThemeMode.dark ? 'dark' : 'light',
    });
    auth =
        _Auth(state)
          ..codeError = codeError
          ..code = code;
    theme = ThemeCubit(await SharedPreferences.getInstance());
    GetIt.I
      ..registerSingleton<AuthCubit>(auth)
      ..registerSingleton<ProfileRepository>(repo)
      ..registerSingleton<StatsDao>(dao)
      ..registerSingleton<PowerupCacheDao>(_FakePowerups())
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<MonetizationService>(money)
      ..registerSingleton<PerksCatalogService>(_FakeCatalog())
      ..registerSingleton<ThemeCubit>(theme)
      ..registerSingleton<TabRefreshBus>(bus)
      ..registerSingleton<LegalLinks>(
        LegalLinks(
          baseUrl: 'https://zanjir.test',
          opener: (u) async {
            openedLinks.add(u);
            return linksLaunch;
          },
        ),
      );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  }

  Widget app({bool reduceMotion = true, double textScale = 1}) {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ZProfileScreen()),
        GoRoute(
          path: '/login',
          builder: (_, state) {
            routes.add(state.uri.toString());
            return const Scaffold(body: Text('login'));
          },
        ),
      ],
    );
    return BlocBuilder<ThemeCubit, ThemeMode>(
      bloc: theme,
      builder:
          (context, mode) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: reduceMotion,
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: child!,
                  ),
                ),
          ),
    );
  }
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

/// Lets the loads, a sheet / dialog entrance and one toast frame run.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 700));
}

/// Runs the clock until no toast is left (a toast owns a 2.6 s timer).
Future<void> _waitForToastToGo(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(loadVazirmatn);

  late _Harness h;

  setUp(() async {
    await GetIt.I.reset();
    h = _Harness();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await GetIt.I.reset();
  });

  Future<void> open(
    WidgetTester tester, {
    AuthState auth = _signedIn,
    ThemeMode mode = ThemeMode.light,
    bool reduceMotion = true,
    double textScale = 1,
    double w = 393,
    double hgt = 852,
  }) async {
    _size(tester, w, hgt);
    await h.register(state: auth, mode: mode);
    await tester.pumpWidget(
      h.app(reduceMotion: reduceMotion, textScale: textScale),
    );
    await _settle(tester);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  group('signed in, free', () {
    testWidgets('shows the real pieces', (tester) async {
      await open(tester);
      expect(find.text('آرش'), findsOneWidget);
      // Level 12 → the title of the 10+ band, the badge and the bar disc.
      expect(find.text('واژه‌باز'), findsOneWidget);
      expect(find.text('۱۲'), findsNWidgets(2));
      expect(find.text('۱۳'), findsOneWidget);
      // Drawn twice (over the track and over the fill) so it reads on amber.
      expect(find.text('$_lri۶۲۰ / ۱٬۰۰۰$_pdi'), findsNWidgets(2));
      // Live coin balance, tappable (carries the «+»).
      expect(find.text('۱٬۲۴۰'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      // Stats.
      expect(find.text('بلندترین زنجیر'), findsOneWidget);
      expect(find.text('۲۳'), findsOneWidget);
      expect(find.text('کلمه'), findsOneWidget);
      expect(find.text('۸۷'), findsOneWidget);
      expect(find.text('بازی‌شده'), findsOneWidget);
      expect(find.text('۵'), findsOneWidget);
      expect(find.text('روز پیاپی'), findsOneWidget);
      expect(find.text('می‌روم'), findsOneWidget);
      // «می‌روم» is 5 letters + a ZWNJ.
      expect(find.text('بلندترین کلمه · ۵ حرف'), findsOneWidget);
      // Free: no crown, the subscription is offered.
      expect(find.text('اشتراک ویژه'), findsNWidgets(2));
      expect(find.text('اشتراک ویژه فعال است'), findsNothing);
      expect(find.byType(ProfileCrown), findsOneWidget);
    });

    testWidgets('the canvas pieces nothing backs stay out', (tester) async {
      await open(tester);
      await scrollTo(tester, find.text('خروج از حساب'));
      for (final omitted in [
        'نشان‌ها',
        'برد آنلاین',
        'کلمهٔ درست',
        'کلمهٔ یکتا ساختی',
        'صدا و لرزش',
        'یادآور',
        'یادآور چالش روزانه',
        'اشتراک‌گذاری',
      ]) {
        expect(find.text(omitted), findsNothing, reason: omitted);
      }
      expect(find.textContaining('عضو از'), findsNothing);
      expect(find.textContaining('دعوت موفق'), findsNothing);
      // The old card's claims that the product does not back.
      expect(find.textContaining('۲۰۰ سکه'), findsNothing);
      expect(find.textContaining('بدون تبلیغ'), findsNothing);
    });

    testWidgets('the XP ring fills to the level progress', (tester) async {
      await open(tester);
      final ring = tester.widgetList<Container>(find.byType(Container)).where((
        c,
      ) {
        final d = c.decoration;
        return d is BoxDecoration && d.gradient is SweepGradient;
      });
      expect(ring, hasLength(1));
      final gradient =
          (ring.single.decoration as BoxDecoration).gradient as SweepGradient;
      expect(gradient.stops, [0, .62, .62, 1]);
      final z = tester.element(find.byType(ProfileHeader)).z;
      expect(gradient.colors.first, z.amber);
      expect(gradient.colors.last, z.wash);
    });

    testWidgets('an empty level shows an empty ring and a zero bar', (
      tester,
    ) async {
      h.repo.stats = const ProfileStats(
        totalMatches: 0,
        wins: 0,
        bestScore: 0,
        bestMatchStreak: 0,
        dailyStreak: 0,
        longestDailyStreak: 0,
        coins: 0,
        level: 1,
        xpInLevel: 0,
        xpForNext: 1000,
      );
      await open(tester);
      expect(find.text('تازه‌کار'), findsOneWidget);
      expect(find.text('$_lri۰ / ۱٬۰۰۰$_pdi'), findsOneWidget);
      // No longest word yet.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('بلندترین کلمه'), findsOneWidget);
    });

    testWidgets('the avatar disc carries the initial', (tester) async {
      await open(tester);
      final disc = tester.widget<ZDiscAvatar>(find.byType(ZDiscAvatar));
      expect(disc.letter, 'آ');
      expect(disc.avatarId, isNull);
    });
  });

  group('signed in, premium', () {
    setUp(() {
      h.repo.perks = PremiumPerks(
        isPremium: true,
        premiumUntil: DateTime.utc(2026, 11, 3, 12),
        avatarId: 'fox',
      );
    });

    testWidgets('crown, the date and the picked avatar', (tester) async {
      await open(tester);
      expect(find.byType(ProfileCrown), findsWidgets);
      await scrollTo(tester, find.text('اشتراک ویژه فعال است'));
      expect(find.text('اشتراک ویژه فعال است'), findsOneWidget);
      expect(find.textContaining('تا ۱۲ آبان ۱۴۰۵'), findsOneWidget);
      expect(find.text('تغییر آواتار'), findsOneWidget);
      // The subscription pitch is gone.
      expect(find.textContaining('ارسال پیام‌های سریع'), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pump();
      expect(
        tester.widget<ZDiscAvatar>(find.byType(ZDiscAvatar)).avatarId,
        'fox',
      );
    });

    testWidgets('picking an avatar saves it and updates the disc', (
      tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('تغییر آواتار'));
      await tester.tap(find.text('تغییر آواتار'));
      await _settle(tester);
      expect(find.text('انتخاب آواتار'), findsOneWidget);
      // The two catalogue avatars (image loads fail in tests → initials).
      expect(find.byType(AvatarTile), findsNWidgets(2));
      await tester.tap(find.byType(AvatarTile).at(1));
      await _settle(tester);
      expect(h.repo.avatarsSet, ['owl']);
      expect(find.text('انتخاب آواتار'), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pump();
      expect(
        tester.widget<ZDiscAvatar>(find.byType(ZDiscAvatar)).avatarId,
        'owl',
      );
    });

    testWidgets('a rejected avatar toasts the Persian reason', (tester) async {
      h.repo.avatarError = const ProfileException(
        'این امکان فقط برای اشتراک ویژه فعال است',
      );
      await open(tester);
      await scrollTo(tester, find.text('تغییر آواتار'));
      await tester.tap(find.text('تغییر آواتار'));
      await _settle(tester);
      await tester.tap(find.byType(AvatarTile).at(1));
      await _settle(tester);
      expect(h.repo.avatarsSet, ['owl']);
      expect(
        find.text('این امکان فقط برای اشتراک ویژه فعال است'),
        findsOneWidget,
      );
      // The disc keeps the old avatar.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pump();
      expect(
        tester.widget<ZDiscAvatar>(find.byType(ZDiscAvatar)).avatarId,
        'fox',
      );
      await _waitForToastToGo(tester);
    });
  });

  group('free subscription card', () {
    testWidgets('lists the real perks and starts the purchase', (tester) async {
      await open(tester);
      await scrollTo(tester, find.text('اشتراک ویژه').last);
      expect(
        find.text('• ارسال پیام‌های سریع حین بازی دو نفره'),
        findsOneWidget,
      );
      expect(find.text('• آواتارهای ویژه و نشان تاج کنار نام'), findsOneWidget);
      expect(find.text('تغییر آواتار'), findsNothing);
      await tester.tap(find.text('اشتراک ویژه').last);
      await _settle(tester);
      expect(h.money.bought, ['premium_monthly']);
      expect(find.text('خرید با موفقیت انجام شد!'), findsOneWidget);
      await _waitForToastToGo(tester);
    });
  });

  group('states', () {
    testWidgets('loading → the mascot, then the profile', (tester) async {
      h.repo.statsGate = Completer<ProfileStats>();
      await open(tester);
      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.text(ZLoadState.loadingLabel), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('آرش'), findsNothing);
      h.repo.statsGate!.complete(_stats);
      await _settle(tester);
      expect(find.byType(ZLoadState), findsNothing);
      expect(find.text('آرش'), findsOneWidget);
    });

    testWidgets('a failed load shows the reason and retry works', (
      tester,
    ) async {
      h.repo.statsError = const ProfileException('بارگذاری پروفایل ناموفق بود');
      await open(tester);
      expect(find.text('بارگذاری پروفایل ناموفق بود'), findsOneWidget);
      expect(find.text('آرش'), findsNothing);
      expect(
        tester.widget<ZMascot>(find.byType(ZMascot)).mood,
        ZMascotMood.sad,
      );
      h.repo.statsError = null;
      await tester.tap(find.text(ZLoadState.retryLabel));
      await _settle(tester);
      expect(find.text('آرش'), findsOneWidget);
      expect(h.repo.statsFetches, 2);
    });

    testWidgets('an unexpected error shows the generic Persian line', (
      tester,
    ) async {
      h.repo.statsError = StateError('boom');
      await open(tester);
      expect(find.text('بارگذاری پروفایل ناموفق بود'), findsOneWidget);
    });

    testWidgets('a failed perks lookup does not break the profile', (
      tester,
    ) async {
      h.repo.perksError = const ProfileException('x');
      await open(tester);
      expect(find.text('آرش'), findsOneWidget);
      expect(find.byType(ProfileCrown), findsOneWidget);
    });
  });

  group('guest', () {
    setUp(() {
      h.dao.local = const LocalPlayerStat(
        id: 1,
        totalMatches: 12,
        wins: 0,
        bestScore: 900,
        bestMatchStreak: 9,
        dailyStreak: 2,
        longestDailyStreak: 4,
        longestWord: 'کتابخانه',
      );
    });

    testWidgets('local stats, nothing fetched, no account pieces', (
      tester,
    ) async {
      await open(tester, auth: const AuthGuest());
      expect(h.repo.statsFetches, 0);
      expect(h.auth.codeFetches, 0);
      expect(find.text('مهمان'), findsOneWidget);
      expect(find.text('در حال بازی به‌صورت مهمان'), findsOneWidget);
      expect(find.text('۱۲'), findsOneWidget);
      expect(find.text('۹'), findsOneWidget);
      expect(find.text('کتابخانه'), findsOneWidget);
      expect(find.text('بلندترین کلمه · ۸ حرف'), findsOneWidget);
      // No level, balance, rename, subscription or invite for a guest.
      expect(find.byType(ZHudCoinPill), findsNothing);
      expect(find.bySemanticsLabel('ویرایش نام کاربری'), findsNothing);
      expect(find.textContaining('۶۲۰'), findsNothing);
      expect(find.text('اشتراک ویژه'), findsNothing);
      expect(find.textContaining('دوستت رو بیار'), findsNothing);
      await scrollTo(tester, find.text('حالت شب'));
      expect(find.text('کد دعوت داری؟'), findsNothing);
      expect(find.text('خروج از حساب'), findsNothing);
    });

    testWidgets('the sign-up card goes to login and back to the profile', (
      tester,
    ) async {
      await open(tester, auth: const AuthGuest());
      await scrollTo(tester, find.text('ثبت‌نام رایگان'));
      await tester.tap(find.text('ثبت‌نام رایگان'));
      await _settle(tester);
      expect(h.routes, ['/login?return=/profile']);
    });

    testWidgets('a guest with no games sees zeroes', (tester) async {
      h.dao.local = null;
      await open(tester, auth: const AuthGuest());
      expect(find.text('مهمان'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('rename: pencil → dialog → saved state and the new name', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('ویرایش نام کاربری'));
      await _settle(tester);
      expect(find.text('نام کاربری'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'سارا_۲');
      await tester.pump();
      await tester.tap(find.text('ذخیره'));
      await _settle(tester);
      expect(h.auth.renamed, ['سارا_۲']);
      // The dialog turns into its success state; the header already follows
      // the live auth state.
      expect(find.text('نام تازه‌ات ثبت شد!'), findsOneWidget);
      await tester.tap(find.text('باشه'));
      await _settle(tester);
      expect(find.text('نام تازه‌ات ثبت شد!'), findsNothing);
      expect(find.text('سارا_۲'), findsOneWidget);
      expect(find.text('آرش'), findsNothing);
    });

    testWidgets('rename: save stays off until the name is new and valid', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('ویرایش نام کاربری'));
      await _settle(tester);
      // Unchanged name.
      await tester.tap(find.text('ذخیره'));
      await _settle(tester);
      expect(h.auth.renamed, isEmpty);
      // Too short, then not allowed characters.
      for (final bad in ['ab', 'ab-cd']) {
        await tester.enterText(find.byType(TextField), bad);
        await tester.pump();
        await tester.tap(find.text('ذخیره'));
        await _settle(tester);
        expect(h.auth.renamed, isEmpty);
      }
      expect(find.text('فقط حرف، عدد و _ مجاز است'), findsOneWidget);
    });

    testWidgets('rename: a taken name keeps the dialog and says why', (
      tester,
    ) async {
      await open(tester);
      h.auth.renameError = const AuthException(
        code: 'username_taken',
        message: 'x',
      );
      await tester.tap(find.bySemanticsLabel('ویرایش نام کاربری'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'مریم');
      await tester.pump();
      await tester.tap(find.text('ذخیره'));
      await _settle(tester);
      expect(h.auth.renamed, ['مریم']);
      expect(find.text('ذخیره'), findsOneWidget);
      expect(find.text(errorMessageFor('username_taken')), findsOneWidget);
      expect(find.text('آرش'), findsOneWidget);
    });

    testWidgets('coins: the pill opens the shop and a bundle is bought', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byType(ZHudCoinPill));
      await _settle(tester);
      expect(find.text('۱۰۰ سکه'), findsOneWidget);
      expect(find.text('۳۵۰ سکه'), findsOneWidget);
      expect(find.text('۱۵۰۰ سکه'), findsOneWidget);
      await tester.tap(find.text('۳۵۰ سکه'));
      await _settle(tester);
      expect(h.money.bought, ['coins_350']);
      expect(find.text('خرید با موفقیت انجام شد!'), findsOneWidget);
      await _waitForToastToGo(tester);
    });

    testWidgets('coins: cancelled and failed purchases toast', (tester) async {
      await open(tester);
      h.money.result = const PurchaseResult(status: PurchaseStatus.cancelled);
      await tester.tap(find.byType(ZHudCoinPill));
      await _settle(tester);
      await tester.tap(find.text('۱۰۰ سکه'));
      await _settle(tester);
      expect(find.text('خرید لغو شد.'), findsOneWidget);
      await _waitForToastToGo(tester);

      h.money.result = const PurchaseResult(status: PurchaseStatus.failed);
      await tester.tap(find.byType(ZHudCoinPill));
      await _settle(tester);
      await tester.tap(find.text('۱۰۰ سکه'));
      await _settle(tester);
      expect(find.text('خرید ناموفق بود.'), findsOneWidget);
      await _waitForToastToGo(tester);
    });

    testWidgets('redeem: a code is sent and the balance follows', (
      tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('کد دعوت داری؟'));
      await tester.tap(find.text('کد دعوت داری؟'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'ab12cd');
      await tester.pump();
      await tester.tap(find.text('ثبت کد'));
      await _settle(tester);
      expect(h.auth.redeemed, ['AB12CD']);
      expect(find.text('خوش اومدی به زنجیر!'), findsOneWidget);
      expect(find.textContaining('سکه‌ها به حساب تو اضافه شد'), findsOneWidget);
      await tester.tap(find.text('بزن بریم'));
      await _settle(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pump();
      // 1240 + 50: the pill is live, not a snapshot.
      expect(find.text('۱٬۲۹۰'), findsOneWidget);
      await _waitForToastToGo(tester);
    });

    testWidgets('redeem: a refused code says why and stays open', (
      tester,
    ) async {
      await open(tester);
      h.auth.redeemError = const AuthException(
        code: 'referral_already_used',
        message: 'x',
      );
      await scrollTo(tester, find.text('کد دعوت داری؟'));
      await tester.tap(find.text('کد دعوت داری؟'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'ZZZZZZ');
      await tester.pump();
      await tester.tap(find.text('ثبت کد'));
      await _settle(tester);
      expect(find.text('ثبت کد'), findsOneWidget);
      expect(
        find.text(errorMessageFor('referral_already_used')),
        findsOneWidget,
      );
      expect((h.auth.state as AuthAuthenticated).coins, 1240);
    });

    testWidgets('redeem: the dialog states what the server pays', (
      tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('کد دعوت داری؟'));
      await tester.tap(find.text('کد دعوت داری؟'));
      await _settle(tester);
      expect(find.text('+۵۰ سکه'), findsNWidgets(2));
      expect(find.text('برای تو'), findsOneWidget);
      expect(find.text('برای دوستت'), findsOneWidget);
      // Empty field: the primary button is the muted one and does nothing.
      await tester.tap(find.text('ثبت کد'));
      await _settle(tester);
      expect(h.auth.redeemed, isEmpty);
      await tester.tap(find.text('کد ندارم'));
      await _settle(tester);
      expect(find.text('برای دوستت'), findsNothing);
    });

    testWidgets('logout asks the auth cubit and the screen turns guest', (
      tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('خروج از حساب'));
      await tester.tap(find.text('خروج از حساب'));
      await _settle(tester);
      expect(h.auth.logouts, 1);
      // Re-keyed by identity: a fresh guest profile, nothing of the account.
      expect(find.text('مهمان'), findsOneWidget);
      expect(find.text('آرش'), findsNothing);
      expect(find.byType(ZHudCoinPill), findsNothing);
    });

    testWidgets('another account replaces the first one', (tester) async {
      await open(tester);
      h.repo.stats = const ProfileStats(
        totalMatches: 3,
        wins: 0,
        bestScore: 0,
        bestMatchStreak: 4,
        dailyStreak: 1,
        longestDailyStreak: 1,
        coins: 0,
        level: 2,
        xpInLevel: 10,
        xpForNext: 1000,
      );
      h.auth.emitState(
        const AuthAuthenticated(userId: 'u2', username: 'سارا', coins: 7),
      );
      await _settle(tester);
      expect(h.repo.statsFetches, 2);
      expect(find.text('سارا'), findsOneWidget);
      expect(find.text('۷'), findsOneWidget);
      expect(find.text('۲۳'), findsNothing);
    });
  });

  group('invite card', () {
    testWidgets('real code, share and copy', (tester) async {
      await open(tester);
      await scrollTo(tester, find.text('دوستت رو بیار، ۵۰ سکه بگیر'));
      expect(find.text('دوستت ۱۰۰ سکه می‌گیرد و تو ۵۰ سکه'), findsOneWidget);
      expect(
        find.text(
          '$_lri'
          'K7M2QX$_pdi',
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('اشتراک‌گذاری کد دعوت'));
      await tester.pump();
      expect(h.share.codes, ['K7M2QX']);

      await tester.tap(
        find.text(
          '$_lri'
          'K7M2QX$_pdi',
        ),
      );
      await _settle(tester);
      expect(h.clipboard, ['K7M2QX']);
      expect(find.text('کد دعوت کپی شد'), findsOneWidget);
      await _waitForToastToGo(tester);
    });

    testWidgets('a failed code is a retry, the profile is untouched', (
      tester,
    ) async {
      h.codeError = StateError('x');
      await open(tester);
      await scrollTo(tester, find.text('کد دعوت بارگذاری نشد'));
      // Only the card failed: stats were fetched once and nothing re-loaded.
      expect(h.repo.statsFetches, 1);
      expect(find.byType(ZLoadState), findsNothing);
      h.auth.codeError = null;
      await tester.tap(find.text('تلاش دوباره'));
      await _settle(tester);
      expect(
        find.text(
          '$_lri'
          'K7M2QX$_pdi',
        ),
        findsOneWidget,
      );
      expect(h.auth.codeFetches, 2);
    });

    testWidgets('the code is never digit-converted', (tester) async {
      h.code = 'AB3K9M';
      await open(tester);
      await scrollTo(tester, find.text('دوستت رو بیار، ۵۰ سکه بگیر'));
      expect(
        find.text(
          '$_lri'
          'AB3K9M$_pdi',
        ),
        findsOneWidget,
      );
    });
  });

  group('theme switch', () {
    testWidgets('toggles night mode and the whole screen follows', (
      tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('حالت شب'));
      final ctx = tester.element(find.text('حالت شب'));
      expect(Theme.of(ctx).brightness, Brightness.light);
      final node = tester.getSemantics(find.bySemanticsLabel('حالت شب'));
      final flags = node.getSemanticsData().flagsCollection;
      expect(flags.isButton, isTrue);
      expect(flags.isToggled, Tristate.isFalse);
      await tester.tap(find.text('حالت شب'));
      await _settle(tester);
      expect(h.theme.state, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.text('حالت شب'))).brightness,
        Brightness.dark,
      );
      // And back.
      await tester.tap(find.text('حالت شب'));
      await _settle(tester);
      expect(h.theme.state, ThemeMode.light);
    });

    testWidgets('the guest has it too', (tester) async {
      await open(tester, auth: const AuthGuest());
      await scrollTo(tester, find.text('حالت شب'));
      await tester.tap(find.text('حالت شب'));
      await _settle(tester);
      expect(h.theme.state, ThemeMode.dark);
    });
  });

  group('tab refresh', () {
    testWidgets('a tap reloads silently and shows no spinner', (tester) async {
      await open(tester);
      h.repo.statsGate = Completer<ProfileStats>();
      h.bus.notify(MainTab.profile);
      await tester.pump();
      expect(h.repo.statsFetches, 2);
      // Content stays; nothing flips back to the loading mascot.
      expect(find.byType(ZLoadState), findsNothing);
      expect(find.text('آرش'), findsOneWidget);
      h.repo.statsGate!.complete(
        const ProfileStats(
          totalMatches: 99,
          wins: 0,
          bestScore: 0,
          bestMatchStreak: 23,
          dailyStreak: 5,
          longestDailyStreak: 9,
          coins: 0,
          level: 12,
          xpInLevel: 620,
          xpForNext: 1000,
        ),
      );
      await _settle(tester);
      expect(find.text('۹۹'), findsOneWidget);
    });

    testWidgets('a failed reload keeps what is on screen', (tester) async {
      await open(tester);
      h.repo.statsError = const ProfileException('x');
      h.bus.notify(MainTab.profile);
      await _settle(tester);
      expect(h.repo.statsFetches, 2);
      expect(find.text('آرش'), findsOneWidget);
      expect(find.text('۸۷'), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('other tabs\' taps are ignored; a failed code is retried', (
      tester,
    ) async {
      h.codeError = StateError('x');
      await open(tester);
      h.bus.notify(MainTab.board);
      h.bus.notify(MainTab.friends);
      await _settle(tester);
      expect(h.repo.statsFetches, 1);
      expect(h.auth.codeFetches, 1);
      h.auth.codeError = null;
      h.bus.notify(MainTab.profile);
      await _settle(tester);
      expect(h.repo.statsFetches, 2);
      expect(h.auth.codeFetches, 2);
      // A code that is already there is not fetched again.
      h.bus.notify(MainTab.profile);
      await _settle(tester);
      expect(h.auth.codeFetches, 2);
    });

    testWidgets('a guest\'s tap reloads the local stats only', (tester) async {
      await open(tester, auth: const AuthGuest());
      h.bus.notify(MainTab.profile);
      await _settle(tester);
      expect(h.repo.statsFetches, 0);
      expect(find.text('مهمان'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('each control is named once, numbers read in full', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(find.bySemanticsLabel('ویرایش نام کاربری'), findsOneWidget);
      // The shared pill also reads its balance after its action.
      expect(
        find.bySemanticsLabel(RegExp(r'^سکه‌ها؛ خرید سکه')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^سطح ۱۲؛ ۶۲۰ از ۱٬۰۰۰ امتیاز$')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^سطح ۱۲؛ ۶۲۰ از ۱٬۰۰۰ امتیاز تا سطح ۱۳$'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('بلندترین زنجیر: ۲۳ کلمه'), findsOneWidget);
      expect(find.bySemanticsLabel('بازی‌شده: ۸۷'), findsOneWidget);
      expect(find.bySemanticsLabel('روز پیاپی: ۵'), findsOneWidget);
      await scrollTo(tester, find.text('خروج از حساب'));
      for (final label in [
        'حالت شب',
        'کد دعوت داری؟',
        'خروج از حساب',
        'اشتراک‌گذاری کد دعوت',
        'کپی کد دعوت',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });
  });

  group('reduced motion', () {
    testWidgets('nothing keeps scheduling frames', (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('layout', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];

    void busy() {
      h.repo.stats = const ProfileStats(
        totalMatches: 999999,
        wins: 0,
        bestScore: 999999,
        bestMatchStreak: 999999,
        dailyStreak: 999999,
        longestDailyStreak: 999999,
        longestWord: 'یک_کلمهٔ_بسیار_بسیار_بسیار_طولانی_برای_آزمایش_سرریز',
        coins: 0,
        level: 100,
        xpInLevel: 999999,
        xpForNext: 999999,
      );
      h.repo.perks = PremiumPerks(
        isPremium: true,
        premiumUntil: DateTime.utc(2030, 1, 1),
        avatarId: 'fox',
      );
    }

    const longName = 'یک_نام_کاربری_خیلی_خیلی_خیلی_بلند_فارسی';
    const rich = AuthAuthenticated(
      userId: 'me-1',
      username: longName,
      coins: 999999,
    );

    for (final size in sizes) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets(
          'busy profile ${size.width.toInt()}×${size.height.toInt()} ${mode.name}',
          (tester) async {
            busy();
            await open(
              tester,
              auth: rich,
              mode: mode,
              w: size.width,
              hgt: size.height,
            );
            expect(tester.takeException(), isNull);
            final list = find.byType(Scrollable).first;
            await tester.drag(list, const Offset(0, -4000));
            await tester.pump();
            expect(tester.takeException(), isNull);
            // The last control is reachable.
            expect(find.text('خروج از حساب'), findsOneWidget);
            final bottom = tester.getRect(find.text('خروج از حساب')).bottom;
            expect(bottom, lessThanOrEqualTo(size.height));
          },
        );

        testWidgets(
          'plain / guest / loading / error ${size.width.toInt()}×${size.height.toInt()} ${mode.name}',
          (tester) async {
            await open(tester, mode: mode, w: size.width, hgt: size.height);
            expect(tester.takeException(), isNull);
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -4000),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            await GetIt.I.reset();
            h = _Harness();
            await open(
              tester,
              auth: const AuthGuest(),
              mode: mode,
              w: size.width,
              hgt: size.height,
            );
            expect(tester.takeException(), isNull);
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -4000),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            await GetIt.I.reset();
            h = _Harness()..repo.statsError = const ProfileException('خطا');
            await open(tester, mode: mode, w: size.width, hgt: size.height);
            expect(tester.takeException(), isNull);

            await GetIt.I.reset();
            h = _Harness()..repo.statsGate = Completer<ProfileStats>();
            await open(tester, mode: mode, w: size.width, hgt: size.height);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('text ×$scale: no overflow, fixed controls capped at 1.3', (
        tester,
      ) async {
        busy();
        await open(tester, auth: rich, textScale: scale, w: 320, hgt: 568);
        expect(tester.takeException(), isNull);

        double scaleOf(String label) => tester
            .renderObject<RenderParagraph>(find.text(label).first)
            .textScaler
            .scale(10);
        // The level bar, the title chip and the name keep their own rules.
        expect(scaleOf('استاد واژه'), closeTo(10 * scale, .01));
        expect(scaleOf(longName), closeTo(10 * scale, .01));
        final word = h.repo.stats.longestWord!;
        final wordLabel =
            'بلندترین کلمه · ${toPersianDigits(letterCount(word))} حرف';
        await scrollTo(tester, find.text(wordLabel));
        expect(scaleOf(wordLabel), closeTo(10 * scale, .01));

        final list = find.byType(Scrollable).first;
        await tester.drag(list, const Offset(0, -4000));
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final fixed in ['حالت شب', 'کد دعوت داری؟', 'خروج از حساب']) {
          expect(scaleOf(fixed), lessThanOrEqualTo(13.01), reason: fixed);
        }
      });
    }

    testWidgets('the coin pill never crowds the avatar on a 320 phone', (
      tester,
    ) async {
      busy();
      await open(tester, auth: rich, w: 320, hgt: 568);
      final pill = tester.getRect(find.byType(ZHudCoinPill));
      final disc = tester.getRect(find.byType(ZDiscAvatar));
      // RTL: the balance is at the start (right), the disc in the middle.
      expect(pill.left, greaterThanOrEqualTo(disc.right - 1));
    });
  });

  group('colours', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('text on its fill is readable (${mode.name})', (
        tester,
      ) async {
        await open(tester, mode: mode);
        final z = tester.element(find.byType(ZProfileScreen)).z;
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onIndigo, z.indigo), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.wash), greaterThanOrEqualTo(4.5));
        expect(
          contrastRatio(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrastRatio(z.coral, z.surface), greaterThanOrEqualTo(3));
        // The bar label is drawn in onAmber over the fill, ink over the track.
        expect(contrastRatio(z.ink, z.wash), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    testWidgets('free light', (tester) async {
      await open(tester);
      await shot(tester, 'z_profile_free_light');
    });

    testWidgets('premium dark', (tester) async {
      h.repo.perks = PremiumPerks(
        isPremium: true,
        premiumUntil: DateTime.utc(2026, 11, 3, 12),
      );
      await open(tester, mode: ThemeMode.dark);
      await shot(tester, 'z_profile_premium_dark');
    });

    testWidgets('lower half dark 320', (tester) async {
      await open(tester, mode: ThemeMode.dark, w: 320, hgt: 568);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await tester.pump();
      await shot(tester, 'z_profile_lower_320_dark');
    });

    testWidgets('guest light', (tester) async {
      await open(tester, auth: const AuthGuest());
      await shot(tester, 'z_profile_guest_light');
    });

    testWidgets('error dark', (tester) async {
      h.repo.statsError = const ProfileException('بارگذاری پروفایل ناموفق بود');
      await open(tester, mode: ThemeMode.dark);
      await shot(tester, 'z_profile_error_dark');
    });

    testWidgets('loading light', (tester) async {
      h.repo.statsGate = Completer<ProfileStats>();
      await open(tester);
      await shot(tester, 'z_profile_loading_light');
    });
  });

  group('legal links', () {
    for (final guest in [false, true]) {
      testWidgets(
        '${guest ? 'guest' : 'signed in'}: both pages open in the browser',
        (tester) async {
          await open(tester, auth: guest ? const AuthGuest() : _signedIn);
          await scrollTo(tester, find.text('قوانین و مقررات'));
          await tester.tap(find.text('قوانین و مقررات'));
          await _settle(tester);
          await tester.tap(find.text('حریم خصوصی'));
          await _settle(tester);
          expect(h.openedLinks.map((u) => u.toString()), [
            'https://zanjir.test/terms',
            'https://zanjir.test/privacy',
          ]);
        },
      );
    }

    testWidgets('the buttons are at least 44dp and labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      await scrollTo(tester, find.text('قوانین و مقررات'));
      for (final label in ['قوانین و مقررات', 'حریم خصوصی']) {
        final box = find.ancestor(
          of: find.text(label),
          matching: find.byType(ProfileChunkButton),
        );
        expect(
          tester.getSize(box).height,
          greaterThanOrEqualTo(44),
          reason: label,
        );
        expect(
          find.bySemanticsLabel('$label، باز کردن در مرورگر'),
          findsOneWidget,
        );
      }
      handle.dispose();
    });

    testWidgets('a browser that will not open shows the Persian toast', (
      tester,
    ) async {
      h.linksLaunch = false;
      await open(tester);
      await scrollTo(tester, find.text('قوانین و مقررات'));
      await tester.tap(find.text('قوانین و مقررات'));
      await _settle(tester);
      expect(find.text(legalPageOpenFailedMessage), findsOneWidget);
      await _waitForToastToGo(tester);
    });
  });
}
