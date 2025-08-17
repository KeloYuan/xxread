import 'package:flutter/material.dart';

extension ColorExtension on Color {
  Color withValues({double? alpha, double? red, double? green, double? blue}) {
    return Color.fromARGB(
      (alpha != null ? (alpha * 255).round().clamp(0, 255) : (a * 255.0).round() & 0xff),
      (red != null ? (red * 255).round().clamp(0, 255) : (r * 255.0).round() & 0xff),
      (green != null ? (green * 255).round().clamp(0, 255) : (g * 255.0).round() & 0xff),
      (blue != null ? (blue * 255).round().clamp(0, 255) : (b * 255.0).round() & 0xff),
    );
  }

  Color withOpacityValues(double opacity) {
    return withAlpha((opacity * 255).round().clamp(0, 255));
  }

  int toARGB32() {
    return (a * 255.0).round() << 24 |
           (r * 255.0).round() << 16 |
           (g * 255.0).round() << 8 |
           (b * 255.0).round();
  }
}