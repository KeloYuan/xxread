// This is a basic Flutter widget test for XX阅读 app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xxread/main.dart';

void main() {
  testWidgets('XX阅读 app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const XxReadApp());

    // Verify that our app shows the expected elements
    expect(find.text('XX阅读'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('书库'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    
    // Verify the empty state message
    expect(find.text('书库空空如也'), findsOneWidget);
    expect(find.text('快来导入你的第一本电子书吧！'), findsOneWidget);

    // Test navigation to library page
    await tester.tap(find.text('书库'));
    await tester.pump();

    // Verify library page content
    expect(find.text('共0本'), findsOneWidget);
    expect(find.text('暂无书籍'), findsOneWidget);

    // Test navigation to settings page
    await tester.tap(find.text('设置'));
    await tester.pump();

    // Verify settings page content
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('字体设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);

    // Test floating action button
    await tester.tap(find.text('首页'));
    await tester.pump();
    
    // Find and tap the import button
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify import page opens
    expect(find.text('导入书籍'), findsOneWidget);
    expect(find.text('导入功能开发中...'), findsOneWidget);
  });
}
