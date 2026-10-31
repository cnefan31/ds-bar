import 'package:flutter/material.dart';

import '../theme.dart';

/// 细描边容器：surface-1 底 + 1px hairline，圆角 10。无投影。
///
/// 这是概览页与设置页唯一的容器样式。设计稿刻意把卡片从六张减到
/// 「主视觉无边框 + 少量细描边容器」，所以这里不再提供高亮/浮层变体。
class DsPanel extends StatelessWidget {
  const DsPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DsColors.surface1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DsColors.hairline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: DsColors.surface3,
        highlightColor: DsColors.surface2,
        child: content,
      ),
    );
  }
}

/// 兼容旧调用：概览页重构后仍用 DsCard 表示细描边容器。
typedef DsCard = DsPanel;

/// 分区标题：左标题 + 可选灰色注记 + 可选右侧动作。
///
/// 上间距 22、下间距 10，与设计稿一致。
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.note,
    this.action,
    this.topSpace = true,
  });

  final String title;
  final String? note;
  final Widget? action;

  /// 页面首个分区可关掉上间距。
  final bool topSpace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: topSpace ? DsSpace.sectionTop : 0,
        bottom: DsSpace.sectionBottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: DsText.section),
          if (note != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                note!,
                style: DsText.sectionNote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// 分区标题的兼容别名。
typedef SectionLabel = SectionHeader;

/// 1px 分隔线。列表行之间使用。
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

/// 列表行：主行标题 + 可选次行 + 尾部区域。
///
/// 触控区最小 44dp，满足 Material 可达性要求。
class DsRow extends StatelessWidget {
  const DsRow({
    super.key,
    required this.title,
    this.sub,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.subMono = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  });

  final String title;
  final String? sub;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  /// 次行是否用等宽字体（用于 sk- 打码、接口地址等）。
  final bool subMono;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 20),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: DsText.rowTitle.copyWith(color: titleColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: subMono
                          ? DsText.rowSub.copyWith(fontFamily: 'monospace')
                          : DsText.rowSub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      splashColor: DsColors.surface3,
      highlightColor: DsColors.surface2,
      child: row,
    );
  }
}

/// 语义点：5dp 圆点，靠颜色表态，不占文字宽度。
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 5});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// 语义色徽章：8% 透明底 + 语义色文字，不用实心色块。
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: color,
        ),
      ),
    );
  }
}

/// 指标格：一等分的竖向小区块，标签淡化、值加重。
///
/// 四个组成一条指标带时，用 [MetricBand] 包一层。
class MetricCell extends StatelessWidget {
  const MetricCell({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: DsText.metricLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: DsText.metric.copyWith(color: valueColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// 指标带：横向等分，格间用 1px 竖线分隔，不用背景色块。
class MetricBand extends StatelessWidget {
  const MetricBand({super.key, required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: DsColors.hairline,
          ),
        );
      }
      children.add(Expanded(child: cells[i]));
    }
    return Row(children: children);
  }
}

/// 就地提示条：用于局部错误（如用量接口失效），不遮挡余额。
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.title,
    required this.detail,
    this.color = DsColors.warning,
    this.actions = const [],
  });

  final String title;
  final String detail;
  final Color color;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: color),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 11,
              height: 1.6,
              color: DsColors.inkMuted,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                actions[i],
              ],
            ]),
          ],
        ],
      ),
    );
  }
}

/// 说明文字：紧跟容器之后的一行小字。
class DsHint extends StatelessWidget {
  const DsHint(this.text, {super.key, this.top = DsSpace.tight});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top),
        child: Text(text, style: DsText.hint),
      );
}

/// 空态：标题 + 说明 + 可选动作。
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.title,
    required this.detail,
    this.action,
  });

  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DsText.emptyTitle),
        const SizedBox(height: 6),
        Text(
          detail,
          style: const TextStyle(fontSize: 12, height: 1.6, color: DsColors.inkSubtle),
        ),
        if (action != null) ...[const SizedBox(height: 14), action!],
      ],
    );
  }
}
