import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG relative luminance of [c].
double relativeLuminance(Color c) {
  double ch(double v) =>
      v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * ch(c.r) + .7152 * ch(c.g) + .0722 * ch(c.b);
}

/// WCAG contrast ratio between two colours (1:1 … 21:1).
double contrastRatio(Color a, Color b) {
  final l1 = relativeLuminance(a);
  final l2 = relativeLuminance(b);
  return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
}
