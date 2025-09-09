// 渐进模糊效果工具类
// Progressive Blur Effects Helper

import 'dart:ui';
import 'package:flutter/material.dart';
import 'color_extensions.dart';

class ProgressiveBlur extends StatelessWidget {
  final Widget child;
  final double startBlur;
  final double endBlur;
  final List<Color> gradientColors;
  final AlignmentGeometry beginAlignment;
  final AlignmentGeometry endAlignment;
  final List<double>? stops;
  final BorderRadius? borderRadius;

  const ProgressiveBlur({
    super.key,
    required this.child,
    this.startBlur = 0.0,
    this.endBlur = 20.0,
    this.gradientColors = const [],
    this.beginAlignment = Alignment.topCenter,
    this.endAlignment = Alignment.bottomCenter,
    this.stops,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = child;

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return Stack(
      children: [
        content,
        // 渐进模糊层
        Positioned.fill(
          child: _buildProgressiveBlurOverlay(context),
        ),
      ],
    );
  }

  Widget _buildProgressiveBlurOverlay(BuildContext context) {
    Widget overlay = BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: (startBlur + endBlur) / 2,
        sigmaY: (startBlur + endBlur) / 2,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: beginAlignment,
            end: endAlignment,
            colors: gradientColors.isNotEmpty 
                ? gradientColors 
                : [
                    Colors.transparent,
                    Theme.of(context).colorScheme.surface.withOpacityValues(0.1),
                    Theme.of(context).colorScheme.surface.withOpacityValues(0.3),
                  ],
            stops: stops ?? [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );

    if (borderRadius != null) {
      overlay = ClipRRect(
        borderRadius: borderRadius!,
        child: overlay,
      );
    }

    return overlay;
  }
}

// 预制的渐进模糊效果
class ProgressiveBlurPresets {
  // 从上到下的渐进模糊 - 适用于AppBar
  static Widget topToBottomBlur({
    required Widget child,
    required BuildContext context,
    double maxBlur = 25.0,
    BorderRadius? borderRadius,
  }) {
    return ProgressiveBlur(
      startBlur: 5.0,
      endBlur: maxBlur,
      beginAlignment: Alignment.topCenter,
      endAlignment: Alignment.bottomCenter,
      gradientColors: [
        Theme.of(context).colorScheme.surface.withOpacityValues(0.95),
        Theme.of(context).colorScheme.surface.withOpacityValues(0.8),
        Theme.of(context).colorScheme.surface.withOpacityValues(0.6),
      ],
      stops: const [0.0, 0.6, 1.0],
      borderRadius: borderRadius,
      child: child,
    );
  }

  // 从中心向外的渐进模糊 - 适用于卡片
  static Widget radialBlur({
    required Widget child,
    required BuildContext context,
    double maxBlur = 20.0,
    BorderRadius? borderRadius,
  }) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.zero,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: maxBlur * 0.7, sigmaY: maxBlur * 0.7),
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [
                      Colors.transparent,
                      Theme.of(context).colorScheme.surface.withOpacityValues(0.1),
                      Theme.of(context).colorScheme.surface.withOpacityValues(0.4),
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 边缘渐进模糊 - 适用于对话框和弹窗
  static Widget edgeBlur({
    required Widget child,
    required BuildContext context,
    double maxBlur = 30.0,
    BorderRadius? borderRadius,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: maxBlur, sigmaY: maxBlur),
            child: child,
          ),
        ),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.zero,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.surface.withOpacityValues(0.9),
                    Theme.of(context).colorScheme.surface.withOpacityValues(0.7),
                    Theme.of(context).colorScheme.surface.withOpacityValues(0.8),
                    Theme.of(context).colorScheme.surface.withOpacityValues(0.95),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 底部导航栏的渐进模糊
  static Widget bottomNavigationBlur({
    required Widget child,
    required BuildContext context,
    double maxBlur = 25.0,
    BorderRadius? borderRadius,
  }) {
    return ProgressiveBlur(
      startBlur: maxBlur,
      endBlur: 5.0,
      beginAlignment: Alignment.bottomCenter,
      endAlignment: Alignment.topCenter,
      gradientColors: [
        Theme.of(context).colorScheme.surface.withOpacityValues(0.95),
        Theme.of(context).colorScheme.surface.withOpacityValues(0.7),
        Colors.transparent,
      ],
      stops: const [0.0, 0.6, 1.0],
      borderRadius: borderRadius,
      child: child,
    );
  }
}

// 高级渐进模糊效果
class AdvancedProgressiveBlur extends StatelessWidget {
  final Widget child;
  final List<BlurLayer> layers;
  final BorderRadius? borderRadius;

  const AdvancedProgressiveBlur({
    super.key,
    required this.child,
    required this.layers,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = child;

    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }

    return Stack(
      children: [
        content,
        ...layers.map((layer) => Positioned.fill(
          child: _buildLayer(context, layer),
        )),
      ],
    );
  }

  Widget _buildLayer(BuildContext context, BlurLayer layer) {
    Widget layerWidget = BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: layer.blur,
        sigmaY: layer.blur,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: layer.gradient ?? LinearGradient(
            colors: [Colors.transparent, layer.color],
          ),
        ),
      ),
    );

    if (borderRadius != null) {
      layerWidget = ClipRRect(borderRadius: borderRadius!, child: layerWidget);
    }

    return layerWidget;
  }
}

// 模糊层配置
class BlurLayer {
  final double blur;
  final Color color;
  final Gradient? gradient;

  const BlurLayer({
    required this.blur,
    required this.color,
    this.gradient,
  });
}