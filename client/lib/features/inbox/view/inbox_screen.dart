import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/inbox/cubit/inbox_cubit.dart';
import 'package:wordchain/features/inbox/data/inbox_repository.dart';

/// Messages screen behind the home bell. Today it only carries referral
/// rewards: "your friend joined with your code — claim N coins".
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  @override
  void initState() {
    super.initState();
    getIt<InboxCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZSpacing.screenGutter, ZSpacing.lg, ZSpacing.screenGutter, ZSpacing.md,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.arrow_forward_rounded, color: z.ink),
                  ),
                  const SizedBox(width: ZSpacing.sm),
                  Text('پیام‌ها', style: ZTypography.screenTitle.copyWith(color: z.ink)),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<InboxCubit, InboxState>(
                bloc: getIt<InboxCubit>(),
                builder: (context, state) {
                  if (state.items.isEmpty) {
                    return Center(
                      child: state.loading
                          ? CircularProgressIndicator(color: z.indigo)
                          : Text(
                              'پیامی نداری',
                              style: ZTypography.body.copyWith(color: z.ink40),
                            ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      ZSpacing.screenGutter, 0, ZSpacing.screenGutter, ZSpacing.xl,
                    ),
                    itemCount: state.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: ZSpacing.md),
                    itemBuilder: (_, i) => _RewardTile(item: state.items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

(String, String) _messageFor(InboxItem item) {
  final coins = toPersianDigits(item.coins);
  switch (item.kind) {
    case 'streak':
      return (
        'پاداش روزهای پیاپی',
        '${toPersianDigits(item.detail)} روز پیاپی بازی کردی! $coins سکه هدیه بگیر.',
      );
    case 'weekly_rank':
      return (
        'پاداش جدول هفتگی',
        'در جدول هفتگی رتبهٔ ${toPersianDigits(item.detail)} شدی! $coins سکه هدیه بگیر.',
      );
    case 'daily_rank':
      return (
        'جایزهٔ چالش روزانه',
        'در چالش دیروز رتبهٔ ${toPersianDigits(item.detail)} شدی! $coins سکه هدیه بگیر.',
      );
    case 'daily_done':
      return ('پاداش چالش روزانه', 'برای شرکت در چالش دیروز $coins سکه هدیه بگیر.');
    case 'daily_login':
      return ('پاداش ورود روزانه', 'برای سر زدن امروز $coins سکه هدیه بگیر.');
    default:
      final name = item.detail.isEmpty ? 'دوستت' : item.detail;
      return ('هدیهٔ دعوت', '$name با کد دعوت تو وارد بازی شد. $coins سکه هدیه بگیر!');
  }
}

class _RewardTile extends StatefulWidget {
  final InboxItem item;

  const _RewardTile({required this.item});

  @override
  State<_RewardTile> createState() => _RewardTileState();
}

class _RewardTileState extends State<_RewardTile> {
  bool _claiming = false;

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final coins = await getIt<InboxCubit>().claim(widget.item.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${toPersianDigits(coins)} سکه به حسابت اضافه شد!')),
      );
    } on InboxException catch (e) {
      // Already claimed elsewhere → resync the list instead of showing an error.
      if (e.code == 'reward_not_found') {
        await getIt<InboxCubit>().refresh();
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('مشکلی پیش آمد، دوباره تلاش کن')));
      }
    }
    if (mounted) setState(() => _claiming = false);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final item = widget.item;
    final (title, body) = _messageFor(item);
    return SolidCard(
      padding: const EdgeInsets.all(ZSpacing.lg),
      radius: ZRadius.cardMax,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: ZTypography.cardTitle.copyWith(color: item.claimed ? z.ink40 : z.ink),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: ZTypography.body.copyWith(color: z.ink60),
          ),
          const SizedBox(height: ZSpacing.md),
          if (item.claimed)
            Text('دریافت شد ✓', style: ZTypography.metaLabel.copyWith(color: z.teal))
          else
            AccentButton(
              label: _claiming ? '...' : 'دریافت ${toPersianDigits(item.coins)} سکه',
              accent: ZAccentColor.amber,
              onPressed: _claiming ? null : _claim,
            ),
        ],
      ),
    );
  }
}
