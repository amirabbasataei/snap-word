import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// Layout and editing rules of the in-game Persian keyboard.
///
/// Rows are listed **right to left** (the first key of a row is the rightmost
/// one — the keyboard forces RTL, so the order is the same in every locale).
/// The three letter rows are the standard Persian layout (Gboard's) with
/// backspace at the end of the third row; the bottom row carries the keys
/// Gboard hides (آ and the hamza forms) around the half-space, with send under
/// the right thumb. Together that is every letter the game accepts
/// (`DictionaryService.hasValidChars`) plus the half-space.
abstract final class ZKeyboardLayout {
  /// ZWNJ (U+200C) — legal *inside* a word, e.g. «می‌روم».
  static const zwnj = '‌';

  static const rows = <List<String>>[
    ['ج', 'ح', 'خ', 'ه', 'ع', 'غ', 'ف', 'ق', 'ث', 'ص', 'ض'],
    ['گ', 'ک', 'م', 'ن', 'ت', 'ا', 'ل', 'ب', 'ی', 'س', 'ش'],
    // Ten letters; backspace is the eleventh key (the rightmost).
    ['چ', 'و', 'پ', 'د', 'ذ', 'ر', 'ز', 'ژ', 'ط', 'ظ'],
  ];

  /// Bottom row, right to left: send, [bottomRight], half-space, [bottomLeft].
  static const bottomRight = ['آ', 'ؤ'];
  static const bottomLeft = ['ء', 'أ', 'ئ'];

  /// Every character the keyboard can type.
  static Set<String> get allKeys => {
    for (final row in rows) ...row,
    ...bottomRight,
    ...bottomLeft,
    zwnj,
  };
}

/// Pure text-editing operations behind the keys, so they can be unit-tested
/// and shared with anything else that drives a [TextEditingController].
abstract final class ZKeyboardEditing {
  /// Types [s] at the caret (replacing a selection). A half-space is ignored
  /// at the start of the word and right after another half-space — neither
  /// can ever be part of a valid word.
  static void insert(TextEditingController c, String s) {
    final text = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    if (s == ZKeyboardLayout.zwnj) {
      final before = text.substring(0, start);
      if (before.isEmpty || before.endsWith(ZKeyboardLayout.zwnj)) return;
    }
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }

  /// Deletes the selection, or the character before the caret.
  static void backspace(TextEditingController c) {
    final text = c.text;
    final sel = c.selection;
    if (!sel.isValid) {
      if (text.isEmpty) return;
      final kept = text.characters.skipLast(1).toString();
      c.value = TextEditingValue(
        text: kept,
        selection: TextSelection.collapsed(offset: kept.length),
      );
      return;
    }
    if (!sel.isCollapsed) {
      c.value = TextEditingValue(
        text: text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    if (sel.start == 0) return;
    final before =
        text.substring(0, sel.start).characters.skipLast(1).toString();
    c.value = TextEditingValue(
      text: before + text.substring(sel.start),
      selection: TextSelection.collapsed(offset: before.length),
    );
  }
}

/// The game's own keyboard: Persian letters, the hamza forms, the half-space,
/// a backspace and a send key — no digits, no space bar, no punctuation. The
/// system keyboard is never shown while it is up (the word field is
/// `TextInputType.none`), so it always has the same height and the chain above
/// it never jumps when the turn passes to the opponent (the keys just dim).
///
/// Looks like the rest of the game: chunky keys with a solid depth edge, the
/// hamza forms tinted indigo, the half-space on `wash`, backspace tinted
/// coral and send in solid teal; every colour comes from [ZColors] /
/// [ZScene], so light and dark are the same widget.
class ZPersianKeyboard extends StatelessWidget {
  /// The word field this keyboard types into.
  final TextEditingController controller;

  /// False dims the keys and ignores touches (the opponent's turn).
  final bool enabled;

  final VoidCallback onSend;

  const ZPersianKeyboard({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  /// Key face height by screen height (the 4 rows are what the chain pays for).
  static double keyHeightFor(double screenHeight) =>
      screenHeight < 600 ? 36.0 : (screenHeight < 700 ? 40.0 : 44.0);

  static const _gap = 4.0;
  static const _depth = 3.0;
  static const _rowGap = 4.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final media = MediaQuery.of(context);
    // Short phones (iPhone SE class) get lower keys so the chain keeps room.
    final keyHeight = ZPersianKeyboard.keyHeightFor(media.size.height);

    Widget letter(String ch, {bool hamza = false}) => _Key(
      flex: 2,
      height: keyHeight,
      label: ch,
      fill: hamza ? z.tintIndigo : z.surface,
      onPress: () => ZKeyboardEditing.insert(controller, ch),
      child: _KeyText(ch),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'کیبورد فارسی',
        child: Container(
          decoration: BoxDecoration(
            color: z.paper,
            border: Border(top: BorderSide(color: zs.outline, width: 3)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsetsDirectional.only(
            start: 6 - _gap / 2,
            end: 6 - _gap / 2,
            top: 8,
            bottom: 6 + media.padding.bottom,
          ),
          child: AbsorbPointer(
            absorbing: !enabled,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : .45,
              duration: const Duration(milliseconds: 120),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < ZKeyboardLayout.rows.length; i++)
                    _KeyRow(
                      height: keyHeight,
                      children: [
                        // Backspace sits above send, under the right thumb
                        // (where Gboard has it).
                        if (i == 2)
                          _Key(
                            flex: 2,
                            height: keyHeight,
                            label: 'پاک کردن',
                            fill: z.tintCoral,
                            repeat: true,
                            onPress:
                                () => ZKeyboardEditing.backspace(controller),
                            child: _Svg(
                              _backspaceSvg(svgHex(z.ink)),
                              width: 22,
                              height: 18,
                            ),
                          ),
                        for (final ch in ZKeyboardLayout.rows[i]) letter(ch),
                      ],
                    ),
                  _KeyRow(
                    height: keyHeight,
                    children: [
                      _Key(
                        flex: 5,
                        height: keyHeight,
                        label: 'بفرست',
                        fill: z.teal,
                        deep: z.tealDeep,
                        highlight: true,
                        commitOnRelease: true,
                        onPress: onSend,
                        child: _Svg(
                          _sendSvg(svgHex(z.onTeal)),
                          width: 26,
                          height: 26,
                        ),
                      ),
                      for (final ch in ZKeyboardLayout.bottomRight)
                        letter(ch, hamza: true),
                      _Key(
                        flex: 7,
                        height: keyHeight,
                        label: 'نیم‌فاصله',
                        fill: z.wash,
                        onPress:
                            () => ZKeyboardEditing.insert(
                              controller,
                              ZKeyboardLayout.zwnj,
                            ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Svg(
                                _halfSpaceSvg(svgHex(z.ink)),
                                width: 22,
                                height: 9,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'نیم‌فاصله',
                                maxLines: 1,
                                style: TextStyle(
                                  color: z.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      for (final ch in ZKeyboardLayout.bottomLeft)
                        letter(ch, hamza: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _backspaceSvg(String ink) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 5h12l6 7-6 7H3a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z"/><path d="M7 9l6 6M13 9l-6 6"/></svg>';

String _sendSvg(String ink) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5M11 6l-6 6 6 6"/></svg>';

/// The «space» bracket with a short tick: a *half* space.
String _halfSpaceSvg(String ink) =>
    '<svg viewBox="0 0 22 9" fill="none" stroke="$ink" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 1v5a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1V1"/><path d="M11 1v3"/></svg>';

class _Svg extends StatelessWidget {
  final String data;
  final double width;
  final double height;

  const _Svg(this.data, {required this.width, required this.height});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.string(data, width: width, height: height),
  );
}

class _KeyText extends StatelessWidget {
  final String text;

  const _KeyText(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    style: TextStyle(
      color: context.z.ink,
      fontWeight: FontWeight.w800,
      fontSize: 22,
      height: 1.1,
    ),
  );
}

/// One row: keys share the width by [_Key.flex] (letter = 2, so a row is 22).
class _KeyRow extends StatelessWidget {
  final double height;
  final List<Widget> children;

  const _KeyRow({required this.height, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ZPersianKeyboard._rowGap),
    child: SizedBox(
      height: height + ZPersianKeyboard._depth + ZGame.outline,
      child: Row(children: children),
    ),
  );
}

/// A chunky key. Commits on pointer *down* (like a real keyboard — typing
/// quickly never waits for a lift), except [commitOnRelease] keys (send: a
/// slipped thumb should be able to slide off). [repeat] keeps firing while
/// held (backspace). The hit area spans half the gap on each side, so there
/// are no dead strips between keys.
class _Key extends StatefulWidget {
  final int flex;
  final double height;
  final String label;
  final Color fill;
  final Color? deep;
  final bool highlight;
  final bool repeat;
  final bool commitOnRelease;
  final VoidCallback onPress;
  final Widget child;

  const _Key({
    required this.flex,
    required this.height,
    required this.label,
    required this.fill,
    required this.onPress,
    required this.child,
    this.deep,
    this.highlight = false,
    this.repeat = false,
    this.commitOnRelease = false,
  });

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _pressed = false;
  Timer? _timer;

  void _fire() {
    HapticFeedback.selectionClick();
    widget.onPress();
  }

  // A pointer event can outlive the key: the turn timer or the game ending
  // swaps the screen while a finger is still down. Every entry point checks.
  void _down(PointerDownEvent _) {
    if (!mounted) return;
    setState(() => _pressed = true);
    if (widget.commitOnRelease) return;
    _fire();
    if (widget.repeat) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 380), () {
        if (!mounted) return;
        _timer = Timer.periodic(
          const Duration(milliseconds: 70),
          (_) => _fire(),
        );
      });
    }
  }

  void _up(PointerUpEvent _) {
    if (!mounted) return;
    _release();
    if (widget.commitOnRelease) _fire();
  }

  void _release() {
    _timer?.cancel();
    _timer = null;
    if (_pressed && mounted) setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pressed: the depth edge is gone and the face sinks by that much.
    final sink = _pressed ? ZPersianKeyboard._depth : 0.0;
    return Expanded(
      flex: widget.flex,
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        onTap: widget.onPress,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerUp: _up,
          onPointerCancel: (_) => _release(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZPersianKeyboard._gap / 2,
            ),
            child: Transform.translate(
              offset: Offset(0, sink),
              child: ChunkyBox(
                fill: widget.fill,
                deep: widget.deep,
                depth: _pressed ? 0 : ZPersianKeyboard._depth,
                radius: 11,
                borderWidth: 2.5,
                highlight: widget.highlight,
                height: widget.height,
                alignment: Alignment.center,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
