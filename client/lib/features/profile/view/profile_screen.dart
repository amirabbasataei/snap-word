import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/profile/cubit/profile_cubit.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authCubit = getIt<AuthCubit>();
    final isGuest = authCubit.isGuest;

    return BlocProvider(
      create: (_) => ProfileCubit(
        repository: getIt<ProfileRepository>(),
        statsDao: getIt(),
        powerupCacheDao: getIt(),
        isGuest: isGuest,
      )..load(),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: BlocBuilder<ProfileCubit, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading || state is ProfileInitial) {
              return const Center(child: CircularProgressIndicator());
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

  void _showBuyCoinsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BuyCoinsSheet(
        onPurchase: (productId) => _purchaseProduct(context, productId),
      ),
    );
  }

  void _purchaseProduct(BuildContext context, String productId) async {
    final monetization = getIt<MonetizationService>();
    final result = await monetization.purchase(productId);
    if (!context.mounted) return;
    final msg = switch (result.status) {
      PurchaseStatus.success => 'Purchase successful!',
      PurchaseStatus.cancelled => 'Purchase cancelled.',
      PurchaseStatus.failed => result.error ?? 'Purchase failed.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _username(BuildContext context) {
    final auth = getIt<AuthCubit>().state;
    if (auth is AuthAuthenticated) return auth.username;
    return 'Guest';
  }

  @override
  Widget build(BuildContext context) {
    final username = _username(context);
    final stats = state.stats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        // Profile header
        _ProfileHeader(username: username, isGuest: state.isGuest),
        const SizedBox(height: 16),

        // Streak + Coins row
        Row(
          children: [
            _InfoChip(
              icon: '🔥',
              label: '${stats.dailyStreak} day${stats.dailyStreak == 1 ? '' : 's'}',
              subLabel: 'Daily streak',
            ),
            const SizedBox(width: 12),
            if (!state.isGuest)
              _InfoChip(
                icon: '🪙',
                label: '${stats.coins}',
                subLabel: 'Coins',
              ),
          ],
        ),

        // Guest registration banner
        if (state.isGuest) ...[
          const SizedBox(height: 16),
          _GuestBanner(onTap: () => context.push('/register')),
        ],

        if (!state.isGuest) ...[
          const SizedBox(height: 12),
          // Buy Coins + Premium buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Text('🪙', style: TextStyle(fontSize: 14)),
                  label: const Text('BUY COINS'),
                  onPressed: () => _showBuyCoinsSheet(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: AppColors.background,
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Text('⭐', style: TextStyle(fontSize: 14)),
                  label: const Text('PREMIUM'),
                  onPressed: () => _purchaseProduct(context, 'premium_monthly'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 24),

        // Stats section
        _SectionLabel('STATS'),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatCard(
              value: '${stats.totalMatches}',
              label: 'Matches played',
            ),
            const SizedBox(width: 10),
            _StatCard(
              value: '${stats.wins}',
              label: 'Wins',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatCard(
              value: '${stats.bestMatchStreak}',
              label: 'Best chain streak',
            ),
            const SizedBox(width: 10),
            _StatCard(
              value: stats.longestWord?.toUpperCase() ?? '—',
              label: stats.longestWord != null
                  ? 'Longest word (${stats.longestWord!.length})'
                  : 'Longest word',
              valueStyle: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),

        // Power-ups section (authenticated only)
        if (!state.isGuest) ...[
          const SizedBox(height: 24),
          _SectionLabel('POWER-UPS'),
          const SizedBox(height: 10),
          _PowerupGrid(powerups: state.powerups),
        ],

        const SizedBox(height: 24),

        // Settings section
        _SectionLabel('SETTINGS'),
        const SizedBox(height: 8),
        _SettingsRow(
          title: 'Tutorial & Help',
          subtitle: 'Replay the tutorial anytime',
          onTap: () async {
            final prefs = getIt<SharedPreferences>();
            await prefs.setBool('tutorial_completed', false);
            if (context.mounted) context.go('/tutorial');
          },
        ),
        if (!state.isGuest)
          _SettingsRow(
            title: 'Remove Ads',
            subtitle: 'One-time purchase · \$2.99',
            onTap: () => _purchaseProduct(context, 'remove_ads'),
          ),
        if (!state.isGuest)
          _SettingsRow(
            title: 'Sign Out',
            subtitle: '',
            onTap: () => getIt<AuthCubit>().logout(),
            isDestructive: true,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final String username;
  final bool isGuest;

  const _ProfileHeader({required this.username, required this.isGuest});

  @override
  Widget build(BuildContext context) {
    final initials = username.isEmpty
        ? '?'
        : username.substring(0, username.length.clamp(0, 2)).toUpperCase();

    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              username,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              isGuest ? 'Playing as guest' : 'WordChain player',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Info chip (streak / coins)
// ---------------------------------------------------------------------------

class _InfoChip extends StatelessWidget {
  final String icon;
  final String label;
  final String subLabel;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
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
  final TextStyle? valueStyle;

  const _StatCard({
    required this.value,
    required this.label,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: valueStyle ??
                  const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Power-up grid
// ---------------------------------------------------------------------------

class _PowerupGrid extends StatelessWidget {
  final List<PowerupItem> powerups;

  const _PowerupGrid({required this.powerups});

  static const _allTypes = ['hint', 'extra_time', 'shield', 'freeze'];
  static const _icons = {
    'hint': '💡',
    'extra_time': '⏱',
    'shield': '🛡',
    'freeze': '❄️',
  };
  static const _labels = {
    'hint': 'Hint',
    'extra_time': 'Extra Time',
    'shield': 'Shield',
    'freeze': 'Freeze',
  };

  @override
  Widget build(BuildContext context) {
    final Map<String, int> qtyMap = {
      for (final p in powerups) p.type: p.quantity,
    };

    return Row(
      children: _allTypes.map((type) {
        final qty = qtyMap[type] ?? 0;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: type == _allTypes.last ? 0 : 8,
            ),
            child: _PowerupCell(
              icon: _icons[type] ?? '?',
              label: _labels[type] ?? type,
              quantity: qty,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PowerupCell extends StatelessWidget {
  final String icon;
  final String label;
  final int quantity;

  const _PowerupCell({
    required this.icon,
    required this.label,
    required this.quantity,
  });

  @override
  Widget build(BuildContext context) {
    final hasAny = quantity > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: hasAny
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color:
                  hasAny ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '×$quantity',
            style: TextStyle(
              color: hasAny ? AppColors.primary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings row
// ---------------------------------------------------------------------------

class _SettingsRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingsRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDestructive
                          ? AppColors.error
                          : AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isDestructive)
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
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
    const coinBundles = [
      ('coins_099', '100 Coins', '\$0.99'),
      ('coins_299', '350 Coins', '\$2.99'),
      ('coins_999', '1500 Coins', '\$9.99'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BUY COINS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 14),
            ...coinBundles.map((bundle) {
              final (id, title, price) = bundle;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onPurchase(id);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        price,
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_upload_outlined,
                color: AppColors.primary, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Register free to save your progress and unlock more power-ups.',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                ),
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppColors.primary, size: 18),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.textSecondary, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              style:
                  const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
