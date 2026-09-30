import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// Shared pieces of the ZSolo/ZPlay/ZVersus game screens — header back
/// button, timer row, powerup tile atom, dashed "next word" tile, and the
/// restyled word-input bar.

/// Back/close button — 34×34 rounded square, `ink60` arrow on `paper`.
class ZBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const ZBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.paper,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: z.line),
        ),
        child: Icon(Icons.arrow_forward, size: 16, color: z.ink60),
      ),
    );
  }
}

/// Confirm-and-end dialog shared by ZSolo/ZPlay's back button.
void zShowEndGameDialog(BuildContext context) {
  final z = context.z;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: z.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZRadius.cardMax),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('پایان بازی؟',
                style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 17)),
            const SizedBox(height: ZSpacing.sm),
            Text(
              'پیشرفت فعلی ذخیره می‌شود.',
              style: ZTypography.body.copyWith(color: z.ink60),
            ),
            const SizedBox(height: ZSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: NeutralButton(
                    label: 'ادامه بازی',
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: AccentButton(
                    accent: ZAccentColor.coral,
                    label: 'پایان بازی',
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      context.read<GameBloc>().add(const GameEnded());
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Numeric countdown + track bar — the turn-timer row atop ZSolo/ZPlay.
class ZTimerRow extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;

  const ZTimerRow({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final fraction =
        totalSeconds <= 0 ? 0.0 : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: ZSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              toPersianDigits(secondsRemaining.toString().padLeft(2, '0')),
              style: ZTypography.cardTitle.copyWith(color: z.coral, fontSize: 15),
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZRadius.chip),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: z.wash,
                valueColor: AlwaysStoppedAnimation(z.coral),
              ),
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Text('ثانیه', style: ZTypography.metaLabel.copyWith(color: z.ink40)),
        ],
      ),
    );
  }
}

/// The hint power-up's glyph — a small indigo badge (matches the canvas's
/// nested `<span>` exactly; the bare "؟" text alone is invisible against
/// the tile's `paper` background since `onIndigo` is white/near-white).
class ZHintIcon extends StatelessWidget {
  const ZHintIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      width: 24,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: z.indigo, borderRadius: BorderRadius.circular(8)),
      child: Text('؟', style: TextStyle(color: z.onIndigo, fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }
}

/// A single power-up slot: icon glyph, top-leading badge count, label below.
class ZPowerupTile extends StatelessWidget {
  final Widget icon;
  final int count;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  final String? priceLabel; // coin cost, shown when no inventory is owned
  final bool dimmed; // looks unavailable (can't afford) but stays tappable

  const ZPowerupTile({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
    required this.enabled,
    this.onTap,
    this.priceLabel,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Expanded(
      child: Column(
        children: [
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: z.paper,
                    borderRadius: BorderRadius.circular(ZRadius.tileMax),
                    border: Border.all(color: z.line),
                    boxShadow: enabled
                        ? ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth)
                        : null,
                  ),
                  child: Opacity(opacity: enabled && !dimmed ? 1 : 0.4, child: icon),
                ),
                if (count > 0)
                  PositionedDirectional(
                  top: -5,
                  start: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: z.ink, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      toPersianDigits(count),
                      style: TextStyle(
                        color: z.paper,
                        fontWeight: FontWeight.w800,
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: ZTypography.metaLabel.copyWith(color: z.ink60, fontSize: 10.5),
          ),
          if (priceLabel != null)
            Text(
              priceLabel!,
              textAlign: TextAlign.center,
              style: ZTypography.metaLabel.copyWith(
                color: z.ink40,
                fontSize: 9.5,
              ),
            ),
        ],
      ),
    );
  }
}

/// The power-up row shared by ZSolo/ZPlay/ZVersus: one [ZPowerupTile] per entry
/// in [types] (`hint`, `freeze`, `extra_time`, `shield`), wired to the bloc.
/// Count = owned inventory; when empty a use costs coins (price shown). Guests
/// see their free-hint allowance, and tapping anything else raises the upsell.
class ZPowerupBar extends StatelessWidget {
  final GameActive state;
  final List<String> types;

  const ZPowerupBar({super.key, required this.state, required this.types});

  static const _labels = {
    'hint': 'راهنما',
    'freeze': 'انجماد حریف',
    'extra_time': 'وقت بیشتر',
    'shield': 'سپر',
  };

  Widget _icon(BuildContext context, String type) {
    final z = context.z;
    switch (type) {
      case 'hint':
        return const ZHintIcon();
      case 'freeze':
        return Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: z.teal,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        );
      case 'extra_time':
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: z.amber, width: 4),
          ),
          child: const SizedBox(width: 22, height: 22),
        );
      default:
        return Container(
          width: 19,
          height: 22,
          decoration: BoxDecoration(
            color: z.coral,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Authenticated players' live balance decides whether a tile looks affordable.
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, auth) {
        final coins = auth is AuthAuthenticated ? auth.coins : 0;
        final isGuest = state.guestHintUsesLeft != 999;
        return Row(
          children: [
            for (var i = 0; i < types.length; i++) ...[
              if (i > 0) const SizedBox(width: ZSpacing.sm),
              _tile(context, types[i], isGuest, coins),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, String type, bool isGuest, int coins) {
    final cost = GameConstants.powerupCostCoins[type]!;
    final owned = isGuest
        ? (type == 'hint' ? state.guestHintUsesLeft : 0)
        : (state.powerupCounts[type] ?? 0);
    final cantAfford = !isGuest && owned == 0 && coins < cost;

    var enabled = GameBloc.canUsePowerup(state, type);
    if (isGuest && type == 'hint' && state.guestHintUsesLeft <= 0) enabled = false;
    // Multiplayer can't wait on an ad, so there an unaffordable tile is just off;
    // solo / vs-AI keep it tappable to offer the rewarded ad.
    if (cantAfford && state.isMultiplayer) enabled = false;

    return ZPowerupTile(
      icon: _icon(context, type),
      count: owned,
      label: _labels[type]!,
      enabled: enabled,
      dimmed: cantAfford,
      priceLabel: !isGuest && owned == 0 ? '${toPersianDigits(cost)} سکه' : null,
      onTap: () {
        if (cantAfford) {
          _showNeedCoinsSheet(context, type, cost - coins);
        } else {
          context.read<GameBloc>().add(PowerupRequested(type));
        }
      },
    );
  }

  Future<void> _showNeedCoinsSheet(BuildContext context, String type, int missing) async {
    final bloc = context.read<GameBloc>();
    // The clocks stop while the sheet (and any ad) is up; solo/vs-AI only.
    bloc.add(const GamePaused());
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _NeedCoinsSheet(powerupLabel: _labels[type]!, missing: missing),
    );
    bloc.add(const GameResumed());
  }
}

/// "Not enough coins" sheet with the rewarded-ad top-up.
class _NeedCoinsSheet extends StatefulWidget {
  final String powerupLabel;
  final int missing;

  const _NeedCoinsSheet({required this.powerupLabel, required this.missing});

  @override
  State<_NeedCoinsSheet> createState() => _NeedCoinsSheetState();
}

class _NeedCoinsSheetState extends State<_NeedCoinsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _watchAd() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final watched = await getIt<MonetizationService>().showRewardedAd();
      if (!watched) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final coins = await getIt<GameRepository>().claimRewardedAd();
      await getIt<AuthCubit>().setCoins(coins);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'اتصال برقرار نشد؛ دوباره تلاش کن';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'سکهٔ کافی برای «${widget.powerupLabel}» نداری',
                style: ZTypography.screenTitle.copyWith(color: z.ink, fontSize: 17),
              ),
              const SizedBox(height: ZSpacing.sm),
              Text(
                'به ${toPersianDigits(widget.missing)} سکهٔ دیگر نیاز داری. '
                'با دیدن یک تبلیغ ${toPersianDigits(GameConstants.rewardedAdCoins)} سکه هدیه بگیر.',
                style: ZTypography.body.copyWith(color: z.ink60),
              ),
              if (_error != null) ...[
                const SizedBox(height: ZSpacing.sm),
                Text(_error!, style: ZTypography.metaLabel.copyWith(color: z.coral)),
              ],
              const SizedBox(height: ZSpacing.xl),
              AccentButton(
                label: _busy
                    ? '…'
                    : 'تماشای تبلیغ (+${toPersianDigits(GameConstants.rewardedAdCoins)} سکه)',
                onPressed: _busy ? null : _watchAd,
              ),
              const SizedBox(height: ZSpacing.sm),
              NeutralButton(label: 'بستن', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed-border letter tile — the "type your next word" placeholder that
/// closes both ZSolo's and ZPlay's chain views.
class ZDashedTile extends StatelessWidget {
  final String letter;
  final double size;

  const ZDashedTile({super.key, required this.letter, this.size = ZTileSize.prompt});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return CustomPaint(
      painter: DashedBorderPainter(radius: 10, color: z.line),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            letter,
            style: ZTypography.chainWordActive.copyWith(color: z.ink40, fontSize: size * 0.5),
          ),
        ),
      ),
    );
  }
}

/// Restyled word-input bar — same functional contract as the legacy
/// `WordInput` (controller/focus/submit), redrawn on tokens: rounded input
/// with a 2px `ink` border + coral caret bar, `teal` send tile with a
/// solid offset edge.
class ZWordInput extends StatefulWidget {
  final String? startLetter;
  final bool enabled;
  final String? hintWord;
  final void Function(String word) onSubmit;
  final bool isOpponentThinking;
  final String opponentLabel;

  const ZWordInput({
    super.key,
    this.startLetter,
    required this.enabled,
    this.hintWord,
    required this.onSubmit,
    this.isOpponentThinking = false,
    this.opponentLabel = 'حریف',
  });

  @override
  State<ZWordInput> createState() => _ZWordInputState();
}

class _ZWordInputState extends State<ZWordInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(ZWordInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hintWord != null && widget.hintWord != oldWidget.hintWord) {
      _controller.text = widget.hintWord!;
      _controller.selection =
          TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final word = _controller.text.trim();
    if (word.isEmpty || !widget.enabled) return;
    widget.onSubmit(word);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;

    if (widget.isOpponentThinking) {
      return Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.paper,
          borderRadius: BorderRadius.circular(ZRadius.cardMin),
          border: Border.all(color: z.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: z.ink40),
            ),
            const SizedBox(width: ZSpacing.sm),
            Text(
              '${widget.opponentLabel} در حال فکر کردن…',
              style: ZTypography.body.copyWith(color: z.ink60, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: z.paper,
              borderRadius: BorderRadius.circular(ZRadius.cardMin),
              border: Border.all(color: z.ink, width: 2),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              textAlign: TextAlign.start,
              cursorColor: z.coral,
              cursorWidth: 2,
              style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 19),
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                isCollapsed: true,
                hintText: widget.startLetter != null
                    ? 'کلمه‌ای با «${widget.startLetter}»…'
                    : 'اولین کلمه رو بنویس…',
                hintStyle: ZTypography.body.copyWith(color: z.ink40),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
        const SizedBox(width: ZSpacing.sm),
        GestureDetector(
          onTap: widget.enabled ? _submit : null,
          child: Container(
            width: 64,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.enabled ? z.teal : z.wash,
              borderRadius: BorderRadius.circular(ZRadius.cardMin),
              boxShadow: widget.enabled
                  ? ZElevation.solidEdge(z.tealDeep, depth: ZElevation.buttonDepth)
                  : null,
            ),
            child: Text(
              'بفرست',
              style: ZTypography.button.copyWith(
                color: widget.enabled ? z.onTeal : z.ink40,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
