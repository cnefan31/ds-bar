import 'package:flutter/material.dart';

import '../theme.dart';

/// 卡片：surface-1 底 + 1px hairline 描边，无投影。
class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // 用 Material 承载背景，ListTile 的水波纹才画得出来。
    final content = SizedBox(
      width: double.infinity,
      child: Material(
        color: DsColors.surface1,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight ? DsColors.hairlineStrong : DsColors.hairline,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: DsColors.surface3,
      highlightColor: DsColors.surface2,
      child: content,
    );
  }
}

/// 分组标题：小写字母间距拉开的标签。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
                color: DsColors.inkSubtle,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 1px 分隔线。
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent, right: endIndent),
        child: const Divider(height: 1, thickness: 1, color: DsColors.hairline),
      );
}

/// 键值行：左侧标签、右侧数值（等宽）。
class StatRow extends StatelessWidget {
  const StatRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.sub,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: DsColors.inkMuted),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub!,
                      style: const TextStyle(fontSize: 11, color: DsColors.inkSubtle),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: DsTheme.mono.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? DsColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// 语义色徽章：8% 透明底 + 语义色文字。
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }
}

/// 提示条：用于展示错误或说明。
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.text,
    this.color = DsColors.warning,
    this.action,
  });

  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.45, color: color),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// 空态。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: DsColors.inkSubtle, height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}
