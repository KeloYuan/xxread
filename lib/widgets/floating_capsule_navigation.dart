import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/glass_config.dart';
import '../utils/color_extensions.dart';

// 悬浮胶囊式导航栏组件
// 仿iOS风格的胶囊选择器，支持毛玻璃效果和平滑动画
class FloatingCapsuleNavigation extends StatefulWidget {
  final List<CapsuleNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final EdgeInsets? margin;
  final double? width;
  final double height;

  const FloatingCapsuleNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    this.margin,
    this.width,
    this.height = 50,
  });

  @override
  State<FloatingCapsuleNavigation> createState() => _FloatingCapsuleNavigationState();
}

class _FloatingCapsuleNavigationState extends State<FloatingCapsuleNavigation>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FloatingCapsuleNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _animationController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: widget.height,
            width: widget.width,
            child: _buildCapsuleNavigation(),
          ),
        );
      },
    );
  }

  Widget _buildCapsuleNavigation() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2), // 胶囊形状
        boxShadow: [
          // 悬浮效果阴影
          BoxShadow(
            color: Colors.black.withOpacityValues(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacityValues(0.05),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height / 2),
        // 毛玻璃效果背景
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: GlassEffectConfig.modalBlur,
            sigmaY: GlassEffectConfig.modalBlur,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacityValues(0.9),
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacityValues(0.2),
                width: 0.5,
              ),
            ),
            child: Stack(
              children: [
                // 滑动指示器背景
                _buildSlideIndicator(),
                // 导航项目
                _buildNavigationItems(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlideIndicator() {
    final itemWidth = 1.0 / widget.items.length;
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: widget.selectedIndex * itemWidth * (widget.width ?? 200),
      top: 4,
      bottom: 4,
      width: itemWidth * (widget.width ?? 200),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacityValues(0.15),
          borderRadius: BorderRadius.circular((widget.height - 8) / 2),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacityValues(0.3),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular((widget.height - 8) / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacityValues(0.1),
                borderRadius: BorderRadius.circular((widget.height - 8) / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationItems() {
    return Row(
      children: widget.items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final isSelected = index == widget.selectedIndex;

        return Expanded(
          child: GestureDetector(
            onTap: () => widget.onItemSelected(index),
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height / 2),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 图标
                    if (item.icon != null) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          item.icon,
                          size: 18,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withOpacityValues(0.6),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    // 文字
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withOpacityValues(0.6),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 14,
                      ),
                      child: Text(item.label),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// 胶囊导航项目数据类
class CapsuleNavigationItem {
  final String label;
  final IconData? icon;
  final Widget? customIcon;

  const CapsuleNavigationItem({
    required this.label,
    this.icon,
    this.customIcon,
  });
}

// 预定义的悬浮导航栏样式
class FloatingCapsuleStyles {
  // 标准样式 (适用于顶部导航)
  static Widget standard({
    required List<CapsuleNavigationItem> items,
    required int selectedIndex,
    required ValueChanged<int> onItemSelected,
  }) {
    return FloatingCapsuleNavigation(
      items: items,
      selectedIndex: selectedIndex,
      onItemSelected: onItemSelected,
      height: 44,
      width: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  // 紧凑样式 (适用于工具栏)
  static Widget compact({
    required List<CapsuleNavigationItem> items,
    required int selectedIndex,
    required ValueChanged<int> onItemSelected,
  }) {
    return FloatingCapsuleNavigation(
      items: items,
      selectedIndex: selectedIndex,
      onItemSelected: onItemSelected,
      height: 36,
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }

  // 宽展样式 (适用于标签页)
  static Widget wide({
    required List<CapsuleNavigationItem> items,
    required int selectedIndex,
    required ValueChanged<int> onItemSelected,
  }) {
    return FloatingCapsuleNavigation(
      items: items,
      selectedIndex: selectedIndex,
      onItemSelected: onItemSelected,
      height: 50,
      width: 280,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );
  }
}

// 使用示例和说明
/*
使用方式：

1. 基本用法：
FloatingCapsuleNavigation(
  items: const [
    CapsuleNavigationItem(label: '图库', icon: Icons.photo_library),
    CapsuleNavigationItem(label: '精选集', icon: Icons.collections),
  ],
  selectedIndex: selectedIndex,
  onItemSelected: (index) {
    setState(() {
      selectedIndex = index;
    });
  },
)

2. 使用预定义样式：
FloatingCapsuleStyles.standard(
  items: navigationItems,
  selectedIndex: currentIndex,
  onItemSelected: onSelectionChanged,
)

3. 自定义样式：
FloatingCapsuleNavigation(
  items: items,
  selectedIndex: selectedIndex,
  onItemSelected: onItemSelected,
  height: 60,           // 自定义高度
  width: 300,           // 自定义宽度
  margin: EdgeInsets.all(20), // 自定义边距
)

特性：
- 毛玻璃背景效果
- 平滑的切换动画
- 悬浮阴影效果
- iOS风格设计
- 支持图标和文字
- 完全可自定义
*/