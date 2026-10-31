import 'package:ds_bar/src/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fmt.money', () {
    test('小额保留两位', () {
      expect(Fmt.money(0), '0.00');
      expect(Fmt.money(1.239), '1.24');
      expect(Fmt.money(42.8), '42.80');
      expect(Fmt.money(99.999), '100.00');
    });

    test('百位以上收敛位数', () {
      expect(Fmt.money(123.44), '123.4');
      expect(Fmt.money(1234), '1,234.0');
    });

    test('千分位与大额', () {
      expect(Fmt.money(12345.67), '12,346');
      expect(Fmt.money(1234567.0), '1,234,567');
    });

    test('null 与非有限值兜底', () {
      expect(Fmt.money(null), '0.00');
      expect(Fmt.money(double.nan), '0.00');
      expect(Fmt.money(double.infinity), '0.00');
    });

    test('负数保留符号与千分位', () {
      expect(Fmt.money(-1234.5), '-1,234.5');
    });
  });

  group('Fmt.moneyExact', () {
    test('固定两位并带千分位', () {
      expect(Fmt.moneyExact(1234.5), '1,234.50');
      expect(Fmt.moneyExact(0), '0.00');
      expect(Fmt.moneyExact(42.8), '42.80');
    });
  });

  group('Fmt.tokens', () {
    test('分级缩写', () {
      expect(Fmt.tokens(999), '999');
      expect(Fmt.tokens(1000), '1.0K');
      expect(Fmt.tokens(1234), '1.2K');
      expect(Fmt.tokens(1234567), '1.23M');
      expect(Fmt.tokens(1234567890), '1.23B');
    });

    test('零与负值归零', () {
      expect(Fmt.tokens(0), '0');
      expect(Fmt.tokens(-5), '0');
      expect(Fmt.tokens(null), '0');
    });
  });

  group('Fmt.count', () {
    test('整数千分位', () {
      expect(Fmt.count(0), '0');
      expect(Fmt.count(1234), '1,234');
      expect(Fmt.count(1234567), '1,234,567');
    });
  });

  group('Fmt.relativeTime', () {
    final now = DateTime(2026, 10, 31, 12, 0);

    test('从未同步', () {
      expect(Fmt.relativeTime(null), '从未');
    });

    test('分钟与小时', () {
      expect(Fmt.relativeTime(now.subtract(const Duration(seconds: 20)), now: now), '刚刚');
      expect(Fmt.relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5 分钟前');
      expect(Fmt.relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3 小时前');
    });

    test('跨天回退到时间戳', () {
      final t = DateTime(2026, 10, 20, 9, 5);
      expect(Fmt.relativeTime(t, now: now), '10-20 09:05');
    });

    test('未来时间也不崩', () {
      expect(Fmt.relativeTime(now.add(const Duration(hours: 1)), now: now), '10-31 13:00');
    });
  });

  group('Fmt 其他', () {
    test('币种符号', () {
      expect(Fmt.currencySymbol('CNY'), '¥');
      expect(Fmt.currencySymbol('USD'), r'$');
      expect(Fmt.currencySymbol(null), '¥');
    });

    test('月份标签补零', () {
      expect(Fmt.monthLabel(2026, 3), '2026-03');
      expect(Fmt.monthLabel(2026, 10), '2026-10');
    });

    test('短日期', () {
      expect(Fmt.shortDate('2026-10-31'), '10-31');
      expect(Fmt.shortDate('bad'), 'bad');
    });
  });
}
