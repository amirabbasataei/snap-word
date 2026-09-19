import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/theme/theme_cubit.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/coin_pill.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/tint_chip.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/view/widgets/referral_bottom_sheet.dart';
import 'package:wordchain/features/profile/cubit/profile_cubit.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

class ZProfileScreen extends StatelessWidget {
  const ZProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // This screen lives inside `_MainShell`'s `StatefulShellRoute.indexedStack`
    // (`app_router.dart`), which keeps every branch's widget alive forever —
    // switching tabs never rebuilds it. Reading `AuthCubit.isGuest` once here
    // meant sign-out (or signing in as a different account) never refreshed
    // this screen; it kept showing whichever account was authenticated when
    // it was first built until the app was killed and relaunched. Caught
    // live on-device testing referral redemption across two accounts.
    // Wrapping in `BlocBuilder<AuthCubit, AuthState>` with a `Key` derived
    // from the identity that matters (guest vs. a specific userId) forces
    // `ProfileCubit` to be recreated — and `.load()` to re-run — on every
    // real auth transition, not just app restarts.
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, authState) {
        final isGuest = authState is! AuthAuthenticated;
        final identity = authState is AuthAuthenticated ? authState.userId : 'guest';
        return BlocProvider(
          key: ValueKey('profile-$identity'),
          create: (_) => ProfileCubit(
            repository: getIt<ProfileRepository>(),
            statsDao: getIt(),
            powerupCacheDao: getIt(),
            isGuest: isGuest,
          )..load(),
          child: const _ProfileView(),
        );
      },
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: BlocBuilder<ProfileCubit, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading || state is ProfileInitial) {
              return Center(child: CircularProgressIndicator(color: z.indigo));
            }
            if (state is ProfileError) {
              return _ErrorView(
                message: state.message,
                onRetry: () => context.read<ProfileCubit>().load(),
              );
            }
            if (state is ProfileLoaded) {
              return _LoadedView(state: state);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded profile view
// ---------------------------------------------------------------------------

class _LoadedView extends StatelessWidget {
  final ProfileLoaded state;

  const _LoadedView({required this.state});

  String _username(BuildContext context) {
    final auth = getIt<AuthCubit>().state;
    if (auth is AuthAuthenticated) return auth.username;
    return 'مهمان';
  }

  void _purchaseProduct(BuildContext context, String productId) async {
    final monetization = getIt<MonetizationService>();
    final result = await monetization.purchase(productId);
    if (!context.mounted) return;
    final msg = switch (result.status) {
      PurchaseStatus.success => 'خرید با موفقیت انجام شد!',
      PurchaseStatus.cancelled => 'خرید لغو شد.',
      PurchaseStatus.failed => result.error ?? 'خرید ناموفق بود.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showBuyCoinsSheet(BuildContext context) {
    final z = context.z;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: z.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZRadius.sheetMax)),
      ),
      builder: (_) => _BuyCoinsSheet(
        onPurchase: (productId) => _purchaseProduct(context, productId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = _username(context);
    final stats = state.stats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZSpacing.screenGutter,
        ZSpacing.lg,
        ZSpacing.screenGutter,
        ZSpacing.xl,
      ),
      children: [
        _ProfileHeader(username: username, isGuest: state.isGuest),
        const SizedBox(height: ZSpacing.xl),

        if (!state.isGuest) ...[
          const _LevelCard(),
          const SizedBox(height: ZSpacing.md),
        ],

        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: toPersianDigits(stats.totalMatches),
                label: 'بازی‌شده',
              ),
            ),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: _StatCard(
                value: toPersianDigits(stats.bestMatchStreak),
                label: 'بلندترین زنجیر',
              ),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.md),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: stats.longestWord?.toUpperCase() ?? '—',
                label: stats.longestWord != null
                    ? 'کلمهٔ بلند (${toPersianDigits(stats.longestWord!.length)})'
                    : 'کلمهٔ بلند',
                fontSize: 18,
              ),
            ),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: _StatCard(
                value: toPersianDigits(stats.dailyStreak),
                label: 'روز پیاپی',
              ),
            ),
          ],
        ),

        if (!state.isGuest) ...[
          const SizedBox(height: ZSpacing.md),
          const _BadgesCard(),
        ],

        const SizedBox(height: ZSpacing.xl),

        if (state.isGuest) ...[
          _GuestBanner(onTap: () => context.push('/login?return=/profile')),
          const SizedBox(height: ZSpacing.xl),
        ] else ...[
          const _LiveCoinRow(),
          const SizedBox(height: ZSpacing.md),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  label: 'خرید سکه',
                  accent: ZAccentColor.amber,
                  onPressed: () => _showBuyCoinsSheet(context),
                ),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: NeutralButton(
                  label: 'اشتراک ویژه',
                  onPressed: () => _purchaseProduct(context, 'premium_monthly'),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.xl),
        ],

        _SectionLabel('تنظیمات'),
        const SizedBox(height: ZSpacing.sm),
        SolidCard(
          padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg),
          radius: ZRadius.cardMax,
          child: Column(
            children: [
              const _NightModeRow(),
              if (!state.isGuest) ...[
                const _CosmeticToggleRow(
                  title: 'صدا و لرزش',
                  valueLabel: 'روشن',
                  showTopBorder: true,
                ),
                const _CosmeticToggleRow(
                  title: 'یادآور چالش روزانه',
                  valueLabel: '۲۱:۰۰',
                  showTopBorder: true,
                ),
                _SettingsRow(
                  title: 'حذف تبلیغات',
                  subtitle: 'خرید یک‌بار · ۲.۹۹ دلار',
                  showTopBorder: true,
                  onTap: () => _purchaseProduct(context, 'remove_ads'),
                ),
                _SettingsRow(
                  title: 'کد دعوت داری؟',
                  subtitle: 'یک‌بار وارد کن، ۵۰ سکه بگیر',
                  showTopBorder: true,
                  onTap: () => ReferralBottomSheet.show(context),
                ),
                _SettingsRow(
                  title: 'خروج از حساب',
                  subtitle: '',
                  showTopBorder: true,
                  isDestructive: true,
                  onTap: () => getIt<AuthCubit>().logout(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Live coin balance
//
// No endpoint anywhere returns a live coin balance for an authenticated user
// (only POST /auth/verify-otp's login response and POST /referral/redeem's
// award do) — `ProfileStats.coins` reads a JSON key the backend's
// statsResponse never sends and is always 0 (same bug already shipped on
// ZHome's top-bar CoinPill, flagged separately, not fixed here since ZHome
// is out of Stage 5's scope). AuthCubit's own `coins` field is the best real
// value available: accurate at login and bumped on referral redemption.
//
// This must be its own `BlocBuilder<AuthCubit, AuthState>` rather than a
// one-time `getIt<AuthCubit>().state` read in `_LoadedView.build` — that
// read is a snapshot, not reactive, so it never picked up the redeem
// sheet's coin bump (`AuthCubit.redeemReferral` emits from AuthCubit, not
// ProfileCubit, so nothing rebuilt this screen). Caught live on-device: the
// snackbar confirmed +50 coins but the pill kept showing ۰ until this fix.
// ---------------------------------------------------------------------------

class _LiveCoinRow extends StatelessWidget {
  const _LiveCoinRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, authState) {
        final coins = authState is AuthAuthenticated ? authState.coins : 0;
        return Row(
          children: [
            CoinPill(amount: coins),
            const Spacer(),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final String username;
  final bool isGuest;

  const _ProfileHeader({required this.username, required this.isGuest});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final initial = username.isEmpty ? '؟' : username.substring(0, 1).toUpperCase();

    return Row(
      children: [
        LetterTile(letter: initial, size: 64, accent: ZAccent.teal, radius: 20, fontSize: 28),
        const SizedBox(width: ZSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 19),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              if (isGuest)
                Text(
                  'در حال بازی به‌صورت مهمان',
                  style: ZTypography.metaLabel.copyWith(color: z.ink40),
                )
              else
                // Level is a placeholder (REDESIGN_PLAN §1 decision 5): no
                // level/XP field exists anywhere in player_stats. Starts
                // truthfully at level 1 rather than copying the canvas's
                // arbitrary "سطح ۱۲" mock content.
                const TintChip(label: 'سطح ۱ · تازه‌کار', tint: ZTint.indigo),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Level / XP card — placeholder (no backend field), flagged.
// ---------------------------------------------------------------------------

class _LevelCard extends StatelessWidget {
  const _LevelCard();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SolidCard(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: ZSpacing.lg),
      radius: ZRadius.cardMax,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('تا سطح ۲', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
              const Spacer(),
              Text(
                '۰ / ۱٬۰۰۰',
                style: ZTypography.metaLabel.copyWith(color: z.ink60, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(ZRadius.chip),
            child: Container(
              height: 10,
              color: z.wash,
              alignment: AlignmentDirectional.centerStart,
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Badges card — placeholder (no backend field), flagged.
// ---------------------------------------------------------------------------

class _BadgesCard extends StatelessWidget {
  const _BadgesCard();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SolidCard(
      padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg, vertical: ZSpacing.lg),
      radius: ZRadius.cardMax,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('نشان‌ها', style: ZTypography.cardTitle.copyWith(color: z.ink)),
              const Spacer(),
              Text('۰ از ۴', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
            ],
          ),
          const SizedBox(height: ZSpacing.md),
          SizedBox(
            height: 48,
            child: ZDashedContainer(
              color: z.line,
              radius: 12,
              padding: EdgeInsets.zero,
              child: SizedBox.expand(
                child: Center(
                  child: Text(
                    'هنوز نشانی باز نکرده‌ای',
                    style: ZTypography.metaLabel.copyWith(color: z.ink40, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat card
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final double fontSize;

  const _StatCard({required this.value, required this.label, this.fontSize = 26});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SolidCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      radius: ZRadius.cardMax,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Vazirmatn',
              fontWeight: FontWeight.w900,
              fontSize: fontSize,
              height: 1.0,
              color: z.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(label, style: ZTypography.metaLabel.copyWith(color: z.ink60)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings rows
// ---------------------------------------------------------------------------

class _NightModeRow extends StatelessWidget {
  const _NightModeRow();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final themeCubit = getIt<ThemeCubit>();
    return BlocBuilder<ThemeCubit, ThemeMode>(
      bloc: themeCubit,
      builder: (context, mode) {
        final isDark = mode == ThemeMode.dark;
        return _SettingsShell(
          title: 'حالت شب',
          showTopBorder: false,
          trailing: GestureDetector(
            onTap: () => themeCubit.toggle(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isDark ? z.ink : z.line,
                borderRadius: BorderRadius.circular(ZRadius.chip),
              ),
              alignment: isDark ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: z.paper, shape: BoxShape.circle),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// صدا و لرزش / یادآور چالش روزانه — rendered per the canvas but with no
/// backend or local persistence behind them (no sound/vibration setting and
/// no notification-scheduling hook exist anywhere in the codebase). Same
/// "build the real interactive UI, wire it to nothing real yet" treatment
/// already applied to ZLobby's wager picker — flagged here and in the
/// Stage 5 report rather than silently faking persistence.
class _CosmeticToggleRow extends StatelessWidget {
  final String title;
  final String valueLabel;
  final bool showTopBorder;

  const _CosmeticToggleRow({
    required this.title,
    required this.valueLabel,
    required this.showTopBorder,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return _SettingsShell(
      title: title,
      showTopBorder: showTopBorder,
      trailing: Text(valueLabel, style: ZTypography.metaLabel.copyWith(color: z.ink40)),
    );
  }
}

class _SettingsShell extends StatelessWidget {
  final String title;
  final bool showTopBorder;
  final Widget trailing;

  const _SettingsShell({
    required this.title,
    required this.showTopBorder,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: showTopBorder ? Border(top: BorderSide(color: z.line)) : null,
      ),
      child: Row(
        children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: z.wash, borderRadius: BorderRadius.circular(9))),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Text(title, style: ZTypography.cardTitle.copyWith(fontSize: 13.5, color: z.ink)),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool showTopBorder;

  const _SettingsRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
    this.showTopBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: showTopBorder ? Border(top: BorderSide(color: z.line)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ZTypography.cardTitle.copyWith(
                      fontSize: 14,
                      color: isDestructive ? z.coral : z.ink,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: ZTypography.metaLabel.copyWith(color: z.ink40)),
                  ],
                ],
              ),
            ),
            if (!isDestructive) Icon(Icons.chevron_left, color: z.ink40, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Text(
      text,
      style: ZTypography.metaLabel.copyWith(color: z.ink40, letterSpacing: 0.4),
    );
  }
}

// ---------------------------------------------------------------------------
// Buy coins bottom sheet
// ---------------------------------------------------------------------------

class _BuyCoinsSheet extends StatelessWidget {
  final void Function(String productId) onPurchase;

  const _BuyCoinsSheet({required this.onPurchase});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    const coinBundles = [
      ('coins_099', '۱۰۰ سکه', '\$۰.۹۹'),
      ('coins_299', '۳۵۰ سکه', '\$۲.۹۹'),
      ('coins_999', '۱۵۰۰ سکه', '\$۹.۹۹'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZSpacing.screenGutter,
          ZSpacing.xl,
          ZSpacing.screenGutter,
          ZSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('خرید سکه'),
            const SizedBox(height: ZSpacing.lg),
            ...coinBundles.map((bundle) {
              final (id, title, price) = bundle;
              return Padding(
                padding: const EdgeInsets.only(bottom: ZSpacing.md),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onPurchase(id);
                  },
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg),
                    decoration: BoxDecoration(
                      color: z.wash,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(width: 20, height: 20, decoration: BoxDecoration(color: z.amber, shape: BoxShape.circle)),
                        const SizedBox(width: ZSpacing.md),
                        Text(title, style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 15)),
                        const Spacer(),
                        Text(
                          price,
                          style: ZTypography.cardTitle.copyWith(color: z.amberDeep, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guest registration banner
// ---------------------------------------------------------------------------

class _GuestBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _GuestBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(ZSpacing.lg),
        decoration: BoxDecoration(
          color: z.tintIndigo,
          borderRadius: BorderRadius.circular(ZRadius.cardMax),
          border: Border.all(color: z.indigo.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: z.indigo, size: 20),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Text(
                'ثبت‌نام رایگان کن تا پیشرفتت ذخیره شود و قدرت‌های بیشتری باز شود.',
                style: ZTypography.body.copyWith(color: z.indigo),
              ),
            ),
            const SizedBox(width: ZSpacing.sm),
            Icon(Icons.chevron_left, color: z.indigo, size: 18),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: z.ink40, size: 48),
            const SizedBox(height: ZSpacing.md),
            Text(message, style: ZTypography.body.copyWith(color: z.ink60), textAlign: TextAlign.center),
            const SizedBox(height: ZSpacing.lg),
            NeutralButton(label: 'تلاش دوباره', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
