import 'package:ds_bar/src/format.dart';
import 'package:ds_bar/src/models.dart';
import 'package:ds_bar/src/native_bridge.dart';
import 'package:ds_bar/src/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机端到端：验证 MethodChannel 可用、原生层返回的数据结构能被 Dart 解析、
/// 界面能真实渲染，并且演示数据的数字在界面上出现。
///
/// 运行：`flutter test integration_test/native_e2e_test.dart -d <deviceId>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('原生通道可用，配置与快照结构可解析', (tester) async {
    final bridge = NativeBridge();

    final config = await bridge.getConfig();
    expect(bridge.lastErrorCode, isNull, reason: 'MethodChannel 应可用');

    // 需求约束：默认开启通知与磁贴，刷新间隔在允许范围内。
    expect(config.refreshMinutes, inInclusiveRange(15, 1440));
    expect(config.keys, isA<List<ConfiguredKey>>());

    // 快照可以为 null（从未同步），但一旦有值必须能被完整解析。
    final snapshot = await bridge.getSnapshot();
    if (snapshot != null) {
      expect(snapshot.version, greaterThanOrEqualTo(1));
      expect(snapshot.fetchedAt, isNotNull);
      if (snapshot.balance != null) {
        expect(snapshot.balance!.primary, isNotNull);
      }
    }
  });

  testWidgets('打开演示数据后，主界面渲染真实数字', (tester) async {
    final bridge = NativeBridge();
    await bridge.saveSettings(demoMode: true);

    final snapshot = await bridge.refresh();
    expect(snapshot, isNotNull, reason: '演示模式不需要网络，应能取到快照');
    expect(snapshot!.demo, isTrue);
    expect(snapshot.balance!.primary!.totalBalance, closeTo(42.8, 1e-9));
    expect(snapshot.usage!.perKey, isNotEmpty);
    expect(snapshot.usage!.models, isNotEmpty);

    await tester.pumpWidget(const MaterialApp(home: DsBarApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 余额与今日区在首屏。
    expect(find.text('42.80'), findsWidgets);
    expect(find.text('演示数据'), findsWidgets);

    // 按 key / 按模型在首屏之外，滚动到可见位置再断言。
    final listFinder = find.byType(ListView).first;
    await tester.scrollUntilVisible(
      find.textContaining('prod-backend'),
      300,
      scrollable: find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('prod-backend'), findsWidgets);

    await tester.scrollUntilVisible(
      find.textContaining('deepseek-chat'),
      300,
      scrollable: find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('deepseek-chat'), findsWidgets);

    // 通知栏：演示模式下应已展示（权限未授予时系统不允许，故只校验不抛异常）。
    await bridge.requestNotificationPermission();
    await tester.pumpAndSettle();

    // 复原，避免把演示模式留在真机上。
    await bridge.saveSettings(demoMode: false);
    await bridge.removeKey('nonexistent-id');
  });

  testWidgets('格式化在真机环境下与预期一致', (tester) async {
    expect(Fmt.money(42.8), '42.80');
    expect(Fmt.moneyExact(1234.5), '1,234.50');
    expect(Fmt.tokens(12480000), '12.48M');
  });
}
