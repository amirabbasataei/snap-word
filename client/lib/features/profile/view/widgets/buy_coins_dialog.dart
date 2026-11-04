import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/services/store_purchase_service.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// The coin shop (canvas `ZCoinShop`, frames 17a/17b): one dialog that picks a
/// pack, shows the connection to Cafe Bazaar inside its own button, and lands
/// on a "coins added" state — no separate progress dialog.
///
/// [onBuy] runs the real purchase. It returns the result, or null when no
/// purchase was started (a guest sent to sign in, one already running); the
/// dialog then closes. A cancelled or failed result returns to the picker (the
/// caller shows the reason).
Future<void> showBuyCoinsDialog(
  BuildContext context, {
  required int balance,
  required Future<StorePurchaseResult?> Function(String productId) onBuy,
}) {
  return showZDialog<void>(context, builder: (_) => BuyCoinsDialog(balance: balance, onBuy: onBuy));
}

class CoinPack {
  final String id;
  final int coins;
  final int toman;

  const CoinPack(this.id, this.coins, this.toman);
}

class BuyCoinsDialog extends StatefulWidget {
  final int balance;
  final Future<StorePurchaseResult?> Function(String productId) onBuy;

  /// Pack ids, coin counts and prices mirror the Cafe Bazaar panel and
  /// `config.StoreProducts` (CLAUDE.md § Cafe Bazaar billing).
  static const packs = [
    CoinPack(StoreProducts.coins100, 100, 9000),
    CoinPack(StoreProducts.coins350, 350, 25000),
    CoinPack(StoreProducts.coins1500, 1500, 79000),
  ];

  /// The picker starts on the middle pack, as in the canvas.
  static const defaultIndex = 1;

  const BuyCoinsDialog({super.key, required this.balance, required this.onBuy});

  /// «۲۱٪ به‌صرفه‌تر»: the saving against the smallest pack's per-coin price;
  /// 0 for the smallest pack itself.
  static int savingPercent(CoinPack p) {
    final base = packs.first.toman / packs.first.coins;
    return ((1 - p.toman / (p.coins * base)) * 100).round();
  }

  @override
  State<BuyCoinsDialog> createState() => _BuyCoinsDialogState();
}

enum _Phase { pick, paying, done }

class _BuyCoinsDialogState extends State<BuyCoinsDialog> {
  int _selected = BuyCoinsDialog.defaultIndex;
  _Phase _phase = _Phase.pick;
  late int _balance = widget.balance;

  CoinPack get _pack => BuyCoinsDialog.packs[_selected];

  Future<void> _buy() async {
    if (_phase == _Phase.paying) return;
    if (_phase == _Phase.done) {
      Navigator.of(context).pop();
      return;
    }
    final pack = _pack;
    setState(() => _phase = _Phase.paying);
    final result = await widget.onBuy(pack.id);
    if (!mounted) return;
    if (result == null) {
      Navigator.of(context).pop();
    } else if (result.status == StorePurchaseStatus.success) {
      setState(() {
        _phase = _Phase.done;
        _balance = result.coins ?? _balance + pack.coins;
      });
    } else {
      setState(() => _phase = _Phase.pick);
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final paying = _phase == _Phase.paying;
    final done = _phase == _Phase.done;
    final pack = _pack;
    return PopScope(
      canPop: !paying,
      child: ZDialogCard(
        semanticLabel: 'خرید سکه',
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 4), child: Center(child: _CoinDisc())),
                  const SizedBox(height: 14),
                  Center(
                    child: Semantics(
                      header: true,
                      child: Text(
                        done ? '${formatPersianNumber(pack.coins)} سکه اضافه شد!' : 'سکه بخر',
                        textAlign: TextAlign.center,
                        style: ZTypography.body.copyWith(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                          color: z.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(child: _BalancePill(balance: _balance)),
                  const SizedBox(height: 20),
                  Semantics(
                    container: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 18,
                      children: [
                        for (var i = 0; i < BuyCoinsDialog.packs.length; i++)
                          _PackRow(
                            pack: BuyCoinsDialog.packs[i],
                            index: i,
                            selected: i == _selected,
                            dimmed: _phase != _Phase.pick && i != _selected,
                            onTap: _phase == _Phase.pick ? () => setState(() => _selected = i) : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _PayButton(
                    label:
                        done
                            ? 'ادامهٔ بازی'
                            : paying
                            ? 'در حال اتصال به کافه‌بازار…'
                            : 'پرداخت ${formatPersianNumber(pack.toman)} تومان',
                    paying: paying,
                    onTap: paying ? null : _buy,
                  ),
                  // The button's resting edge already takes 7 of the 14.
                  const SizedBox(height: 7),
                  _Note(text: done ? 'خریدت ثبت شد.' : 'پرداخت امن از کافه‌بازار'),
                ],
              ),
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: _CloseButton(onTap: paying ? null : () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

const _closeSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" '
    'viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="3.2" '
    'stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';

const _checkSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" '
    'viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="4" '
    'stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';

const _lockSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" '
    'viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.6" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<rect x="5" y="11" width="14" height="10" rx="2"/>'
    '<path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>';

const _spinnerSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" '
    'viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="3" '
    'stroke-linecap="round"><path d="M12 3a9 9 0 1 1-9 9"/></svg>';

Widget _svg(String template, Color color, double size) =>
    SvgPicture.string(template.replaceAll('{c}', svgHex(color)), width: size, height: size);

/// 44×44 tap target, the ✕ drawn 18dp (canvas: top 8 / left 8 of the card).
class _CloseButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'بستن',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Center(child: _svg(_closeSvg, context.z.ink60, 18))),
      ),
    );
  }
}

/// 60dp amber disc with the 26dp ring (`border 3.5 amberDeep`).
class _CoinDisc extends StatelessWidget {
  const _CoinDisc();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ExcludeSemantics(
      child: ChunkyBox(
        fill: z.amber,
        circle: true,
        depth: 4,
        width: 60,
        height: 60,
        alignment: Alignment.center,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: z.amberDeep, width: 3.5)),
        ),
      ),
    );
  }
}

class _BalancePill extends StatelessWidget {
  final int balance;

  const _BalancePill({required this.balance});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Container(
      height: 30,
      padding: const EdgeInsetsDirectional.only(start: 12, end: 10),
      decoration: BoxDecoration(
        color: z.wash,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: zs.outline, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: z.amber,
              border: Border.all(color: zs.outline, width: 2),
            ),
          ),
          Text(
            'موجودی:',
            style: ZTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w800, height: 1.2, color: z.ink60),
          ),
          Text(
            '${formatPersianNumber(balance)} سکه',
            style: ZTypography.body.copyWith(fontSize: 14, fontWeight: FontWeight.w900, height: 1.2, color: z.ink),
          ),
        ],
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  final CoinPack pack;
  final int index;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  const _PackRow({
    required this.pack,
    required this.index,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final saving = BuyCoinsDialog.savingPercent(pack);
    final fg = selected ? z.onAmber : z.ink;
    final big = index == BuyCoinsDialog.packs.length - 1;
    final label =
        '${formatPersianNumber(pack.coins)} سکه، '
        '${formatPersianNumber(pack.toman)} تومان'
        '${saving > 0 ? '، ${toPersianDigits(saving)}٪ به‌صرفه‌تر' : ''}';
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: dimmed ? .45 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            transform: Matrix4.translationValues(0, selected ? -2 : 0, 0),
            // The tag overhangs the top edge, so it must not be clipped.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ChunkyBox(
                  fill: selected ? z.amber : z.wash,
                  depth: selected ? 4 : 0,
                  radius: 18,
                  highlight: selected,
                  height: 72,
                  padding: const EdgeInsetsDirectional.only(start: 14, end: 12),
                  child: Row(
                    spacing: 12,
                    children: [
                      _CoinStack(count: index + 1),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatPersianNumber(pack.coins),
                              style: ZTypography.body.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                height: 1.25,
                                color: fg,
                              ),
                            ),
                            Text(
                              'سکه',
                              style: ZTypography.body.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                                color: z.ink60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatPersianNumber(pack.toman),
                            style: ZTypography.body.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                              color: fg,
                            ),
                          ),
                          Text(
                            'تومان',
                            style: ZTypography.body.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              color: z.ink60,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? z.teal : z.surface,
                          border: Border.all(color: zs.outline, width: 3),
                        ),
                        child: selected ? _svg(_checkSvg, z.onTeal, 14) : null,
                      ),
                    ],
                  ),
                ),
                if (saving > 0)
                  PositionedDirectional(
                    top: -12,
                    start: 64,
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: big ? z.coral : z.indigo,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: zs.outline, width: 2.5),
                      ),
                      child: Text(
                        '${toPersianDigits(saving)}٪ به‌صرفه‌تر',
                        style: ZTypography.body.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          height: 17 / 11,
                          color: big ? z.onCoral : z.onIndigo,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1–3 overlapping 28dp coins in a 52×34 slot, each 9dp further along, the
/// odd ones lifted 3dp, the first on top.
class _CoinStack extends StatelessWidget {
  final int count;

  const _CoinStack({required this.count});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return ExcludeSemantics(
      child: SizedBox(
        width: 52,
        height: 34,
        child: Stack(
          children: [
            // Painted back to front: coin 0 is the top one.
            for (var k = count - 1; k >= 0; k--)
              PositionedDirectional(
                start: k * 9.0,
                top: 3.0 + (k.isOdd ? -3 : 0),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: zs.outline, width: 2.5),
                    color: z.amber,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.alphaBlend(const Color(0x59FFFFFF), z.amber), z.amber],
                      stops: const [0, .55],
                    ),
                  ),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: z.amberDeep, width: 2)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final String label;
  final bool paying;
  final VoidCallback? onTap;

  const _PayButton({required this.label, required this.paying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Opacity(
      opacity: paying ? .85 : 1,
      child: ChunkyPressable(
        depth: 4,
        onTap: onTap,
        semanticLabel: label,
        builder:
            (context, depth, pressed) => ChunkyBox(
              fill: z.teal,
              deep: z.tealDeep,
              depth: depth,
              radius: 18,
              height: 56,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  if (paying) _Spinner(color: z.onTeal),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: ZTypography.button.copyWith(
                        fontSize: 17,
                        color: z.onTeal,
                        shadows: [Shadow(color: z.tealDeep, offset: const Offset(0, 2))],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

/// The 270° arc turning once per 0.8s; still under reduced motion.
class _Spinner extends StatefulWidget {
  final Color color;

  const _Spinner({required this.color});

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (homeReducedMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(child: RotationTransition(turns: _c, child: _svg(_spinnerSvg, widget.color, 18)));
  }
}

class _Note extends StatelessWidget {
  final String text;

  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 6,
      children: [
        ExcludeSemantics(child: _svg(_lockSvg, z.ink60, 13)),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(fontSize: 12, fontWeight: FontWeight.w700, height: 1.5, color: z.ink60),
          ),
        ),
      ],
    );
  }
}
