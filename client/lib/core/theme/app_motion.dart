import 'package:flutter/animation.dart';

/// Motion specs from the design token sheet (`Zanjir.dc.html`, section 4b).
abstract final class ZMotion {
  /// Tile drop / word commit.
  static const tileDrop = Duration(milliseconds: 180);
  static const tileDropCurve = Curves.easeOutBack;

  /// Bubble enter in a chat-style chain (fade + 8px slide).
  static const bubbleEnter = Duration(milliseconds: 140);
  static const bubbleEnterCurve = Curves.easeOut;
  static const bubbleEnterSlide = 8.0;

  /// Timer bar ticks linearly; caller swaps its colour to `coral` under 5s.
  static const timerTick = Duration(seconds: 1);
  static const timerTickCurve = Curves.linear;
  static const timerDangerThreshold = Duration(seconds: 5);

  /// Wrong-word shake: two 90ms cycles at 6px amplitude.
  static const shakeCycle = Duration(milliseconds: 90);
  static const shakeCycles = 2;
  static const shakeAmplitude = 6.0;

  /// Light/dark cross-fade — colour only, no layout change.
  static const themeSwitch = Duration(milliseconds: 200);
  static const themeSwitchCurve = Curves.linear;
}
