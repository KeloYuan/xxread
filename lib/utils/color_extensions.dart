import 'package:flutter/material.dart';

// 辅助函数替换已弃用的withOpacity和color属性
extension ColorOpacity on Color {
  Color withOpacityValues(double opacity) {
    return withValues(alpha: opacity);
  }
}