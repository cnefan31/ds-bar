/// 金额 / token 数 / 时间的展示格式化。全部为纯函数，便于单测。
class Fmt {
  /// 金额：小额保留两位，大额收敛位数。传入 null 视为 0。
  static String money(num? v, {int decimals = 2}) {
    final value = (v ?? 0).toDouble();
    if (!value.isFinite) return '0.00';
    final mag = value.abs();
    if (mag >= 10000) return _groupFixed(value, 0);
    if (mag >= 1000) return _groupFixed(value, 1);
    if (mag >= 100) return value.toStringAsFixed(1);
    return value.toStringAsFixed(decimals);
  }

  /// 精确金额：用于对账场景，固定两位并带千分位。
  static String moneyExact(num? v) => _groupFixed((v ?? 0).toDouble(), 2);

  static String _groupFixed(double v, int decimals) {
    final fixed = v.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    final negative = intPart.startsWith('-');
    final digits = negative ? intPart.substring(1) : intPart;
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    final sign = negative ? '-' : '';
    return parts.length > 1 ? '$sign$buffer.${parts[1]}' : '$sign$buffer';
  }

  /// token 数：K / M / B。
  static String tokens(num? v) {
    final value = (v ?? 0).toDouble();
    if (!value.isFinite || value <= 0) return '0';
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(2)}B';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(2)}M';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return value.round().toString();
  }

  /// 请求次数：千分位整数。
  static String count(num? v) => _groupFixed((v ?? 0).toDouble(), 0);

  static String currencySymbol(String? currency) => currency == 'USD' ? r'$' : '¥';

  /// 相对时间：刚刚 / N 分钟前 / N 小时前 / MM-dd HH:mm。
  static String relativeTime(DateTime? time, {DateTime? now}) {
    if (time == null) return '从未';
    final base = now ?? DateTime.now();
    final diff = base.difference(time);
    if (diff.isNegative) return _stamp(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return _stamp(time);
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  static String monthLabel(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  /// 日期 'yyyy-MM-dd' → 'MM-dd'。
  static String shortDate(String date) =>
      date.length >= 10 ? date.substring(5, 10) : date;
}
