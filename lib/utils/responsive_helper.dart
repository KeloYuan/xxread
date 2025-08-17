import 'package:flutter/material.dart';

class ResponsiveHelper {
  // 屏幕尺寸断点
  static const double tabletBreakpoint = 768.0;
  static const double desktopBreakpoint = 1200.0;
  
  // 判断是否为手机
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < tabletBreakpoint;
  }
  
  // 判断是否为平板
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= tabletBreakpoint && width < desktopBreakpoint;
  }
  
  // 判断是否为桌面
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= desktopBreakpoint;
  }
  
  // 判断是否为宽屏设备（平板或桌面）
  static bool isWideScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }
  
  // 获取屏幕类型
  static ScreenType getScreenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopBreakpoint) {
      return ScreenType.desktop;
    } else if (width >= tabletBreakpoint) {
      return ScreenType.tablet;
    } else {
      return ScreenType.mobile;
    }
  }
  
  // 根据屏幕类型返回不同的值
  static T getValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    switch (getScreenType(context)) {
      case ScreenType.desktop:
        return desktop ?? tablet ?? mobile;
      case ScreenType.tablet:
        return tablet ?? mobile;
      case ScreenType.mobile:
        return mobile;
    }
  }
  
  // 获取响应式边距
  static double getHorizontalPadding(BuildContext context) {
    return getValue(
      context,
      mobile: 16.0,
      tablet: 32.0,
      desktop: 64.0,
    );
  }
  
  // 获取响应式列数
  static int getColumnCount(BuildContext context, {
    int mobileColumns = 1,
    int? tabletColumns,
    int? desktopColumns,
  }) {
    return getValue(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns ?? mobileColumns * 2,
      desktop: desktopColumns ?? tabletColumns ?? mobileColumns * 3,
    );
  }
  
  // 获取响应式字体大小
  static double getFontSize(
    BuildContext context, {
    required double baseFontSize,
    double? tabletScale,
    double? desktopScale,
  }) {
    final scale = getValue(
      context,
      mobile: 1.0,
      tablet: tabletScale ?? 1.1,
      desktop: desktopScale ?? 1.2,
    );
    return baseFontSize * scale;
  }
  
  // 获取书库网格的纵横比
  static double getBookGridAspectRatio(BuildContext context) {
    return getValue(
      context,
      mobile: 0.7,
      tablet: 0.8,
      desktop: 0.9,
    );
  }
  
  // 获取书库网格的列数
  static int getBookGridColumns(BuildContext context) {
    return getValue(
      context,
      mobile: 2,
      tablet: 3,
      desktop: 4,
    );
  }
  
  // 判断是否应该显示双页布局
  static bool shouldShowDoublePage(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    
    // 横屏且宽度足够时显示双页
    return width > height && width >= tabletBreakpoint;
  }
  
  // 获取导航栏类型
  static NavigationType getNavigationType(BuildContext context) {
    if (isDesktop(context) || isTablet(context)) {
      return NavigationType.rail;
    } else {
      return NavigationType.bottom;
    }
  }
}

enum ScreenType {
  mobile,
  tablet,
  desktop,
}

enum NavigationType {
  bottom,
  rail,
}