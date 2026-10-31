import 'dart:convert';

import 'package:ds_bar/src/app_state.dart';
import 'package:ds_bar/src/native_bridge.dart';
import 'package:ds_bar/src/theme.dart';
import 'package:ds_bar/src/ui/app.dart';
import 'package:ds_bar/src/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用打桩的 MethodChannel 驱动真实界面，校验渲染结果而不依赖图片比对。
class _FakeChannel {
  _FakeChannel({required this.config, required this.snapshot});

  Map<String, dynamic> config;
  Map<String, dynamic>? snapshot;
  int refreshCalls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
      switch (call.method) {
        case 'getConfig':
          return jsonEncode(config);
        case 'getSnapshot':
          return snapshot == null ? null : jsonEncode(snapshot);
        case 'refresh':
          refreshCalls++;
          return snapshot == null ? null : jsonEncode(snapshot);
        case 'appendKey':
        case 'removeKey':
        case 'saveSettings':
          return jsonEncode(config);
        case 'requestNotificationPermission':
        case 'openUrl':
        case 'openQsTileSettings':
          return true;
        default:
          return null;
      }
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, null);
  }
}

Map<String, dynamic> _demoSnapshot() => {
      'version': 1,
      'fetchedAt': DateTime(2026, 10, 31, 12).millisecondsSinceEpoch,
      'currency': 'CNY',
      'demo': true,
      'balance': {
        'isAvailable': true,
        'infos': [
          {
            'currency': 'CNY',
            'totalBalance': 42.8,
            'grantedBalance': 2.8,
            'toppedUpBalance': 40.0,
          }
        ],
      },
      'usage': {
        'year': 2026,
        'month': 10,
        'currency': 'CNY',
        'monthTotal': {'tokens': 12480000, 'cost': 18.4271, 'requests': 3640},
        'today': {'tokens': 486000, 'cost': 0.7124, 'requests': 128},
        'models': [
          {
            'model': 'deepseek-chat',
            'usage': {'tokens': 9120000, 'cost': 12.8172, 'cacheHit': 6700000, 'cacheMiss': 1520000}
          }
        ],
        'days': [
          {'date': '2026-10-01', 'tokens': 341000, 'cost': 1.03},
          {'date': '2026-10-02', 'tokens': 382000, 'cost': 1.17},
        ],
        'perKey': [
          {
            'name': 'prod-backend',
            'hasKey': true,
            'month': {'tokens': 7400000, 'cost': 11.24, 'requests': 2160},
            'today': {'tokens': 210000, 'cost': 0.42},
          },
          {
            'name': 'dev-local',
            'hasKey': true,
            'month': {'tokens': 3280000, 'cost': 4.81, 'requests': 1020},
            'today': {'tokens': 160000, 'cost': 0.21},
          },
        ],
        'perKeyTracked': true,
      },
      'keyChecks': [
        {'id': 'a', 'name': 'prod-backend', 'masked': 'sk-ab…9f2c', 'ok': true}
      ],
    };

Widget _wrap(Widget child) => MaterialApp(
      theme: DsTheme.build(),
      darkTheme: DsTheme.build(),
      themeMode: ThemeMode.dark,
      home: Scaffold(body: child),
    );

/// 把测试画布调成足够高，避免 ListView 懒加载把下方内容判为不存在。
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('配置完整时概览页渲染余额、今日、按 key、按模型', (tester) async {
    _useTallSurface(tester);
    final fake = _FakeChannel(
      config: {
        'keys': [
          {'id': 'a', 'name': 'prod-backend'}
        ],
        'refreshMinutes': 60,
        'notifyEnabled': true,
        'tileEnabled': true,
        'demoMode': true,
        'userTokenSet': true,
        'cookieSet': false,
        'lastRefreshAt': 0,
      },
      snapshot: _demoSnapshot(),
    )..install();
    addTearDown(fake.uninstall);

    final state = AppState()..load();
    await tester.pumpWidget(_wrap(AnimatedBuilder(
      animation: state,
      builder: (_, _) => _HomeHost(state: state),
    )));
    await tester.pumpAndSettle();

    // 余额大额数字
    expect(find.text('42.80'), findsOneWidget);
    // 币种符号
    expect(find.text('¥'), findsOneWidget);
    // 演示数据标记
    expect(find.text('演示数据'), findsWidgets);
    // 今日三项指标
    expect(find.text('¥0.71'), findsOneWidget); // 今日消费
    expect(find.text('486.0K'), findsOneWidget); // 今日 tokens
    expect(find.text('128'), findsOneWidget); // 今日请求
    // 本月合计
    expect(find.text('12.48M'), findsWidgets);
    expect(find.text('3,640 次请求'), findsOneWidget);
    // 按 key
    expect(find.text('prod-backend'), findsWidgets);
    expect(find.text('dev-local'), findsOneWidget);
    expect(find.text('7.40M tokens'), findsOneWidget);
    // 按模型
    expect(find.text('deepseek-chat'), findsOneWidget);
    expect(find.text('9.12M tokens · 73.1%'), findsOneWidget);
    // key 状态
    expect(find.text('有效'), findsOneWidget);
    expect(find.text('sk-ab…9f2c'), findsOneWidget);
  });

  testWidgets('无凭据时给出配置引导，不显示 0 元余额', (tester) async {
    _useTallSurface(tester);
    final fake = _FakeChannel(
      config: {
        'keys': <Map<String, dynamic>>[],
        'refreshMinutes': 60,
        'notifyEnabled': true,
        'tileEnabled': true,
        'demoMode': false,
        'userTokenSet': false,
      },
      snapshot: {
        'version': 1,
        'fetchedAt': DateTime(2026, 10, 31, 12).millisecondsSinceEpoch,
        'currency': 'CNY',
        'balanceError': {'code': 'missing_credential', 'message': '未添加 API Key'},
        'usageError': {'code': 'missing_credential', 'message': '未配置平台 userToken'},
        'keyChecks': <Map<String, dynamic>>[],
      },
    )..install();
    addTearDown(fake.uninstall);

    final state = AppState()..load();
    await tester.pumpWidget(_wrap(AnimatedBuilder(
      animation: state,
      builder: (_, _) => _HomeHost(state: state),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有添加 API Key'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    // 余额拿不到时用「未配置凭据」而不是「余额不足」
    expect(find.text('未配置凭据'), findsOneWidget);
    expect(find.text('余额不足'), findsNothing);
  });

  testWidgets('切换设置页可渲染各分组', (tester) async {
    _useTallSurface(tester);
    final fake = _FakeChannel(
      config: {
        'keys': [
          {'id': 'a', 'name': 'prod-backend'}
        ],
        'refreshMinutes': 30,
        'notifyEnabled': true,
        'tileEnabled': true,
        'demoMode': false,
        'userTokenSet': true,
      },
      snapshot: _demoSnapshot(),
    )..install();
    addTearDown(fake.uninstall);

    await tester.pumpWidget(_wrap(const DsBarApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();

    expect(find.text('凭据'), findsOneWidget);
    expect(find.text('API Keys'), findsOneWidget);
    expect(find.text('通知栏与磁贴'), findsOneWidget);
    expect(find.text('刷新'), findsWidgets);
    expect(find.text('数据来源'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
    expect(find.textContaining('api.deepseek.com/user/balance'), findsOneWidget);
  });
}

/// 直接使用真实 HomePage，避免测试与生产布局分叉。
class _HomeHost extends StatelessWidget {
  const _HomeHost({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) =>
      HomePage(state: state, onOpenSettings: () {});
}
