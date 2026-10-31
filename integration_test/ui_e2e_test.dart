import 'package:ds_bar/src/native_bridge.dart';
import 'package:ds_bar/src/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机端到端：验证概览页与设置页在真实设备上渲染出预期结构。
///
/// 不依赖截图，改用 widget 树断言，避免受锁屏/息屏影响。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('打开演示数据后概览页渲染四段结构', (tester) async {
    final bridge = NativeBridge();
    await bridge.saveSettings(demoMode: true);
    final snapshot = await bridge.refresh();
    expect(snapshot, isNotNull);
    expect(snapshot!.demo, isTrue);

    await tester.pumpWidget(const MaterialApp(home: DsBarApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 主视觉：余额大字
    expect(find.text('42.80'), findsWidgets);
    // 四段分区标题
    expect(find.text('今日'), findsWidgets);
    expect(find.text('本月'), findsWidgets);
    expect(find.text('按 Key'), findsWidgets);
    // 演示数据标记
    expect(find.text('演示数据'), findsWidgets);
    // 余额拆分三项
    expect(find.text('充值'), findsWidgets);
    expect(find.text('赠送'), findsWidgets);
    expect(find.text('今日已花'), findsWidgets);

    await bridge.saveSettings(demoMode: false);
  });

  testWidgets('设置页渲染连接状态与两段凭据', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DsBarApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('连接状态'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('平台会话'), findsOneWidget);
    expect(find.text('解锁用量'), findsOneWidget);
    expect(find.text('解锁余额'), findsOneWidget);
    expect(find.text('刷新'), findsWidgets);
    expect(find.text('数据来源'), findsOneWidget);
  });

  testWidgets('测试连接通道返回结构化结果', (tester) async {
    final bridge = NativeBridge();
    final result = await bridge.testConnection();
    // 未配置任何凭据时应返回结果（而非 null），且各项标记为未配置
    expect(result, isNotNull);
    expect(result!.items, isNotEmpty);
    expect(result.allOk, isFalse);
  });
}
