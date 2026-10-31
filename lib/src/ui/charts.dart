import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// 每日 token 用量柱状图。纯 CustomPainter，无第三方图表依赖。
class DailyBarChart extends StatelessWidget {
  const DailyBarChart({
    super.key,
    required this.days,
    this.height = 128,
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
          child: Text('暂无每日数据', style: TextStyle(fontSize: 12, color: DsColors.inkTertiary)),
        ),
      );
    }
    final values = days.map((d) => showCost ? d.cost : d.tokens.toDouble()).toList();
    final maxValue = values.fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _BarPainter(
              values: values,
              maxValue: maxValue,
              dates: days.map((d) => d.date).toList(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              days.first.date.length >= 5 ? days.first.date.substring(5) : days.first.date,
              style: const TextStyle(fontSize: 10, color: DsColors.inkTertiary),
            ),
            Text(
              days.last.date.length >= 5 ? days.last.date.substring(5) : days.last.date,
              style: const TextStyle(fontSize: 10, color: DsColors.inkTertiary),
            ),
          ],
        ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.values, required this.maxValue, required this.dates});

  final List<double> values;
  final double maxValue;
  final List<String> dates;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;

    // 网格线：hairline 三条
    final gridPaint = Paint()
      ..color = DsColors.hairline
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * (i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final count = values.length;
    final slot = size.width / count;
    final barWidth = math.min(slot * 0.62, 18.0);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    final barPaint = Paint()..color = DsColors.primary.withValues(alpha: 0.85);
    final emptyPaint = Paint()..color = DsColors.surface3;

    for (var i = 0; i < count; i++) {
      final v = values[i];
      final h = v <= 0 ? 2.0 : math.max(2.0, (v / safeMax) * (size.height - 4));
      final left = slot * i + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - h, barWidth, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, v <= 0 ? emptyPaint : barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.values != values || old.maxValue != maxValue;
}

/// 用量构成条：缓存命中 / 缓存未命中 / 输出，三段比例条。
class CompositionBar extends StatelessWidget {
  const CompositionBar({super.key, required this.bucket});

  final UsageBucket bucket;

  @override
  Widget build(BuildContext context) {
    final total = bucket.tokens;
    if (total <= 0) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: DsColors.surface3,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    final segments = <(double, Color, String)>[
      (bucket.cacheHit / total, DsColors.primary, '缓存命中'),
      (bucket.cacheMiss / total, DsColors.warning, '缓存未命中'),
      (bucket.output / total, DsColors.success, '输出'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(
              children: segments
                  .where((s) => s.$1 > 0)
                  .map(
                    (s) => Expanded(
                      flex: math.max(1, (s.$1 * 1000).round()),
                      child: Container(color: s.$2),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: segments
              .map(
                (s) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: s.$2, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.$3,
                      style: const TextStyle(fontSize: 11, color: DsColors.inkSubtle),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
