import 'dart:convert';

import 'package:ds_bar/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Json 工具兜底', () {
    test('类型不符时退回默认值', () {
      expect(Json.numOr('abc'), 0);
      expect(Json.numOr(null, 1.5), 1.5);
      expect(Json.numOr('12.5'), 12.5);
      expect(Json.intOr('7'), 7);
      expect(Json.intOr(7.9), 8);
      expect(Json.str(null, 'x'), 'x');
      expect(Json.str('', 'x'), 'x');
      expect(Json.str(''), '');
      expect(Json.str('abc'), 'abc');
      expect(Json.flag('true'), true);
      expect(Json.flag(null, true), true);
      expect(Json.list('notalist'), isEmpty);
      expect(Json.map('notamap'), isNull);
    });

    test('numOr 过滤 NaN', () {
      expect(Json.numOr(double.nan), 0);
      expect(Json.numOr(double.infinity, 3), 3);
    });
  });

  group('Snapshot 解析', () {
    test('完整快照', () {
      final json = {
        'version': 1,
        'fetchedAt': 1761900000000,
        'currency': 'CNY',
        'demo': false,
        'balance': {
          'isAvailable': true,
          'infos': [
            {
              'currency': 'CNY',
              'totalBalance': 42.5,
              'grantedBalance': 2.5,
              'toppedUpBalance': 40.0,
            }
          ],
        },
        'usage': {
          'year': 2026,
          'month': 10,
          'currency': 'CNY',
          'monthTotal': {'tokens': 1000, 'cost': 1.5, 'requests': 10},
          'today': {'tokens': 100, 'cost': 0.2},
          'models': [
            {
              'model': 'deepseek-chat',
              'usage': {'tokens': 1000, 'cost': 1.5}
            }
          ],
          'days': [
            {'date': '2026-10-01', 'tokens': 500, 'cost': 0.7}
          ],
          'perKey': [
            {
              'name': 'prod',
              'hasKey': true,
              'month': {'tokens': 800, 'cost': 1.2},
              'today': {'tokens': 50, 'cost': 0.1}
            }
          ],
          'perKeyTracked': true,
        },
        'keyChecks': [
          {'id': 'a', 'name': 'prod', 'masked': 'sk-ab…12', 'ok': true}
        ],
      };

      final snap = Snapshot.fromJson(json);
      expect(snap, isNotNull);
      expect(snap!.currency, 'CNY');
      expect(snap.balance!.isAvailable, isTrue);
      expect(snap.balance!.primary!.totalBalance, 42.5);
      expect(snap.usage!.monthTotal.tokens, 1000);
      expect(snap.usage!.models.single.model, 'deepseek-chat');
      expect(snap.usage!.days.single.date, '2026-10-01');
      expect(snap.usage!.perKey.single.name, 'prod');
      expect(snap.usage!.perKeyTracked, isTrue);
      expect(snap.keyChecks.single.masked, 'sk-ab…12');
      expect(snap.fetchedAt, DateTime.fromMillisecondsSinceEpoch(1761900000000));
    });

    test('缺字段不抛异常', () {
      final snap = Snapshot.fromJson({'version': 1});
      expect(snap, isNotNull);
      expect(snap!.balance, isNull);
      expect(snap.usage, isNull);
      expect(snap.keyChecks, isEmpty);
      expect(snap.fetchedAt, isNull);
    });

    test('类型错乱也不抛异常', () {
      final snap = Snapshot.fromJson({
        'balance': 'not-an-object',
        'usage': 42,
        'keyChecks': {'a': 1},
        'fetchedAt': 'yesterday',
      });
      expect(snap, isNotNull);
      expect(snap!.balance, isNull);
      expect(snap.usage, isNull);
      expect(snap.keyChecks, isEmpty);
    });

    test('null / 非对象输入返回 null', () {
      expect(Snapshot.fromJson(null), isNull);
      expect(Snapshot.fromJson('[]'), isNull);
    });

    test('JSON 字符串往返', () {
      final raw = jsonEncode({
        'version': 1,
        'currency': 'USD',
        'balance': {
          'isAvailable': false,
          'infos': [
            {'currency': 'USD', 'totalBalance': 0.0}
          ],
        },
      });
      final snap = Snapshot.fromJson(jsonDecode(raw));
      expect(snap!.currency, 'USD');
      expect(snap.balance!.isAvailable, isFalse);
      expect(snap.balance!.primary!.currency, 'USD');
    });
  });

  group('UsageBucket', () {
    test('缓存命中率', () {
      const b = UsageBucket(cacheHit: 80, cacheMiss: 20, output: 30, tokens: 130);
      expect(b.cacheHitRate, closeTo(0.8, 1e-9));
    });

    test('无输入时命中率为 null', () {
      const b = UsageBucket(output: 30, tokens: 30);
      expect(b.cacheHitRate, isNull);
    });
  });

  group('AppConfig 解析', () {
    test('默认值', () {
      final cfg = AppConfig.fromJson({});
      expect(cfg.refreshMinutes, 60);
      expect(cfg.notifyEnabled, isTrue);
      expect(cfg.tileEnabled, isTrue);
      expect(cfg.demoMode, isFalse);
      expect(cfg.keys, isEmpty);
      expect(cfg.usageReady, isFalse);
    });

    test('keys 与开关', () {
      final cfg = AppConfig.fromJson({
        'keys': [
          {'id': 'a', 'name': 'prod'}
        ],
        'refreshMinutes': 30,
        'notifyEnabled': false,
        'userTokenSet': true,
        'lastRefreshAt': 1000,
      });
      expect(cfg.keys.single.name, 'prod');
      expect(cfg.refreshMinutes, 30);
      expect(cfg.notifyEnabled, isFalse);
      expect(cfg.usageReady, isTrue);
      expect(cfg.lastRefreshAt, DateTime.fromMillisecondsSinceEpoch(1000));
    });
  });

  _probeTests();

  group('ApiIssue 提示语', () {
    test('已知错误码映射', () {
      expect(const ApiIssue(code: 'auth_failed', message: '').hint, 'API Key 无效');
      expect(const ApiIssue(code: 'platform_auth', message: '').hint, 'userToken 已过期');
      expect(const ApiIssue(code: 'unknown_thing', message: '').hint, '获取失败');
    });
  });
}

/// 设置页新增能力的解析测试。
void _probeTests() {
  group('ProbeResult 解析', () {
    test('完整结果', () {
      final r = ProbeResult.fromJson({
        'allOk': false,
        'testedAt': 1761900000000,
        'items': [
          {'target': 'apiKey', 'label': 'API Key · prod', 'ok': true, 'detail': '200 · ¥42.80'},
          {'target': 'platform', 'label': '平台 userToken', 'ok': false, 'detail': '401 未授权', 'code': 'platform_auth'},
        ],
      });
      expect(r, isNotNull);
      expect(r!.items, hasLength(2));
      expect(r.okCount, 1);
      expect(r.failCount, 1);
      expect(r.allOk, isFalse);
      expect(r.testedAt, DateTime.fromMillisecondsSinceEpoch(1761900000000));
      expect(r.items[1].code, 'platform_auth');
    });

    test('失败项给中文解释', () {
      const auth = ProbeItem(target: 'platform', label: 'x', code: 'platform_auth');
      expect(auth.hint, contains('过期'));
      const missing = ProbeItem(target: 'apiKey', label: 'x', code: 'missing_credential');
      expect(missing.hint, '尚未配置');
      const unknown = ProbeItem(target: 'x', label: 'x', code: 'zzz');
      expect(unknown.hint, '未知问题');
    });

    test('缺字段与类型错乱不抛异常', () {
      final r = ProbeResult.fromJson({'items': 'notalist'});
      expect(r, isNotNull);
      expect(r!.items, isEmpty);
      expect(r.allOk, isFalse);
      expect(ProbeResult.fromJson(null), isNull);
    });

    test('全通过时 allOk 为真', () {
      final r = ProbeResult.fromJson({
        'allOk': true,
        'items': [
          {'target': 'apiKey', 'label': 'k', 'ok': true, 'detail': '200'},
        ],
      });
      expect(r!.allOk, isTrue);
      expect(r.failCount, 0);
    });
  });

  group('ConfiguredKey 打码', () {
    test('解析 masked 字段', () {
      final k = ConfiguredKey.fromJson({'id': 'a', 'name': 'prod', 'masked': 'sk-ab…9f2c'});
      expect(k.masked, 'sk-ab…9f2c');
    });

    test('缺 masked 时为空串，不报错', () {
      final k = ConfiguredKey.fromJson({'id': 'a', 'name': 'prod'});
      expect(k.masked, '');
    });
  });
}
