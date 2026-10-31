import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// 每日 token 趋势图。纯 CustomPainter，无第三方图表依赖。
///
/// 设计规范：柱宽自适应、间距 3、圆角 1.5 仅顶部；
/// 最新一日实色，其余 42% 透明；三条 hairline 网格。
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.days,
    this.height = 76,
    this.showCost = false,
  });

  final List<DayUsage> days;
  final double height;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            '暂无每日数据',
            style: TextStyle(fontSize: 11, color: DsColors.inkTertiary),
          ),
        ),
      );
    }
    final values =
        days.map((d) => showCost ? d.cost : d.tokens.toDouble()).toList();
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _TrendPainter(values: values),
        size: Size.infinite,
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;

    final gridPaint = Paint()
      ..color = DsColors.hairline
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * (i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxValue = values.fold<double>(0, math.max);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    final count = values.length;
    final slot = size.width / count;
    final barWidth = math.min(slot * 0.72, 16.0);
    final radius = const Radius.circular(1.5);

    for (var i = 0; i < count; i++) {
      final v = values[i];
      final isLast = i == count - 1;
      final h = v <= 0
          ? 2.0
          : math.max(2.0, (v / safeMax) * (size.height - 2));
      final left = slot * i + (slot - barWidth) / 2;
      final paint = Paint()
        ..color = isLast
            ? DsColors.primary
            : DsColors.primary.withValues(alpha: 0.42);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - h, barWidth, h),
          topLeft: radius,
          topRight: radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.values != values;
}

/// 趋势图容器：标题行 + 图 + 两端日期。
class TrendBlock extends StatelessWidget {
  const TrendBlock({
    super.key,
    required this.days,
    required this.title,
    this.note,
  });

  final List<DayUsage> days;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: DsColors.inkSubtle),
            ),
            const Spacer(),
            if (note != null)
              Text(
                note!,
                style: const TextStyle(
                  fontSize: 11,
                  color: DsColors.inkTertiary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TrendChart(days: days),
        if (days.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_short(days.first.date), style: _axisStyle),
              Text(_short(days.last.date), style: _axisStyle),
            ],
          ),
        ],
      ],
    );
  }

  static const _axisStyle = TextStyle(fontSize: 9, color: DsColors.inkTertiary);

  static String _short(String date) =>
      date.length >= 10 ? date.substring(5) : date;
}

/// 横向占比条：用于模型或 key 的份额对比。
///
/// 单个模型时退化为一条实色，不画空心比例。
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.segments, this.height = 8});

  /// (权重, 颜色) 列表。权重应已归一或可相对比较。
  final List<(double, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, e) => s + e.$1);
    if (total <= 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: DsColors.surface3,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final (weight, color) in segments)
              if (weight > 0)
                Expanded(
                  flex: math.max(1, (weight / total * 1000).round()),
                  child: ColoredBox(color: color),
                ),
          ],
        ),
      ),
    );
  }
}

/// 用量构成条：缓存命中 / 未命中 / 输出，三段比例。
class CompositionBar extends StatelessWidget {
  const CompositionBar({super.key, required this.bucket});

  final UsageBucket bucket;

  @override
  Widget build(BuildContext context) {
    final segments = <(double, Color)>[
      (bucket.cacheHit.toDouble(), DsColors.primary),
      (bucket.cacheMiss.toDouble(), DsColors.warning),
      (bucket.output.toDouble(), DsColors.success),
    ];
    if (bucket.tokens <= 0) {
      return ShareBar(segments: const [], height: 6);
    }
    return ShareBar(segments: segments, height: 6);
  }
}
