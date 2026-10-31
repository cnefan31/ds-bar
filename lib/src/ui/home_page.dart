import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'charts.dart';
import 'common.dart';

/// 概览页。
///
/// 结构（自上而下）：
///  1. 主视觉区 —— 余额独占一级视觉，下接「充值 / 赠送 / 今日已花」三项拆分
///  2. 今日 —— 消费 / token / 请求 / 命中率 四格指标带
///  3. 本月 —— 逐日趋势
///  4. 按 Key —— 列表 + 占比条
///  5. 按 Model —— 占比条 + 列表
///  6. 凭据状态 —— 列表 + 语义点
///
/// 刻意不复用「六张同权重卡片」的旧结构：层级靠字号与留白，不靠边框。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state, required this.onOpenSettings});

  final AppState state;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    final config = state.config;

    if (state.loading && snapshot == null) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: DsColors.primary),
        ),
      );
    }

    final hasCredentials = config.keys.isNotEmpty || config.userTokenSet;

    return RefreshIndicator(
      onRefresh: () => state.refresh(),
      color: DsColors.primary,
      backgroundColor: DsColors.surface2,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          DsSpace.screenH,
          DsSpace.normal,
          DsSpace.screenH,
          40,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (!hasCredentials && !config.demoMode)
            _FirstRunGuide(onOpenSettings: onOpenSettings)
          else if (snapshot == null)
            DsPanel(
              padding: const EdgeInsets.all(16),
              child: EmptyHint(
                title: '还没有数据',
                detail: '下拉刷新，或点右上角同步。',
                action: FilledButton(
                  onPressed: () => state.refresh(),
                  child: const Text('立即同步'),
                ),
              ),
            )
          else ...[
            _HeroBlock(snapshot: snapshot),
            if (snapshot.usageError != null && snapshot.balance != null) ...[
              const SizedBox(height: DsSpace.normal),
              _UsageErrorNotice(
                error: snapshot.usageError!,
                onOpenSettings: onOpenSettings,
              ),
            ],
            const SizedBox(height: DsSpace.normal),
            _TodayBlock(usage: snapshot.usage),
            if (snapshot.usage != null) ...[
              _MonthBlock(usage: snapshot.usage!),
              _PerKeyBlock(state: state, usage: snapshot.usage!),
              _PerModelBlock(usage: snapshot.usage!),
            ],
            _CredentialBlock(snapshot: snapshot),
            const SizedBox(height: 18),
            Center(
              child: Text(
                '更新于 ${Fmt.relativeTime(snapshot.fetchedAt)}',
                style: const TextStyle(fontSize: 10, color: DsColors.inkTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 主视觉区：无边框，直接铺在画布上。
class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.snapshot});

  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final info = snapshot.balance?.primary;
    final sym = Fmt.currencySymbol(info?.currency ?? snapshot.currency);
    final available = snapshot.balance?.isAvailable ?? false;
    final todayCost = snapshot.usage?.today?.cost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 可用状态行：5dp 语义点 + 一句话。
        Row(
          children: [
            StatusDot(
              color: info == null
                  ? DsColors.inkTertiary
                  : (available ? DsColors.success : DsColors.danger),
            ),
            const SizedBox(width: 7),
            Text(
              info == null
                  ? (snapshot.balanceError?.hint ?? '不可用')
                  : (available ? '可用' : '余额不足'),
              style: const TextStyle(fontSize: 10.5, color: DsColors.inkSubtle),
            ),
            if (snapshot.demo) ...[
              const SizedBox(width: 8),
              const StatusBadge(label: '演示数据', color: DsColors.warning),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // 余额：全页唯一的一级视觉。
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(sym, style: DsText.heroSym),
            const SizedBox(width: 2),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  info == null ? '——' : Fmt.moneyExact(info.totalBalance),
                  style: info == null
                      ? DsText.hero.copyWith(color: DsColors.inkTertiary)
                      : DsText.hero,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 三项拆分：充值 / 赠送 / 今日已花。
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: DsColors.hairline)),
          ),
          child: MetricBand(
            cells: [
              MetricCell(
                label: '充值',
                value: info == null
                    ? '——'
                    : '$sym${Fmt.moneyExact(info.toppedUpBalance)}',
              ),
              MetricCell(
                label: '赠送',
                value: info == null
                    ? '——'
                    : '$sym${Fmt.moneyExact(info.grantedBalance)}',
              ),
              MetricCell(
                label: '今日已花',
                value: todayCost == null ? '——' : '−$sym${Fmt.money(todayCost)}',
                valueColor:
                    todayCost == null ? DsColors.inkTertiary : DsColors.warning,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 今日四格。用量缺失时整块换成提示，不显示 0。
class _TodayBlock extends StatelessWidget {
  const _TodayBlock({required this.usage});

  final Usage? usage;

  @override
  Widget build(BuildContext context) {
    if (usage == null) return const SizedBox.shrink();
    final today = usage!.today;
    final sym = Fmt.currencySymbol(usage!.currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('今日'),
        DsPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: today == null
              ? Text('今日用量不可用', style: DsText.hint)
              : MetricBand(
                  cells: [
                    MetricCell(label: '消费', value: '$sym${Fmt.money(today.cost)}'),
                    MetricCell(label: 'TOKEN', value: Fmt.tokens(today.tokens)),
                    MetricCell(label: '请求', value: Fmt.count(today.requests)),
                    MetricCell(
                      label: '命中',
                      value: today.cacheHitRate == null
                          ? '——'
                          : '${(today.cacheHitRate! * 100).toStringAsFixed(1)}%',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 本月逐日趋势。
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({required this.usage});

  final Usage usage;

  @override
  Widget build(BuildContext context) {
    if (usage.days.isEmpty) return const SizedBox.shrink();
    final sym = Fmt.currencySymbol(usage.currency);
    final peak = usage.days.fold<int>(0, (m, d) => d.tokens > m ? d.tokens : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          '本月',
          note:
              '${Fmt.count(usage.monthTotal.requests)} 次 · $sym${Fmt.money(usage.monthTotal.cost)}',
        ),
        DsPanel(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
          child: TrendBlock(
            days: usage.days,
            title: '每日 token',
            note: '峰值 ${Fmt.tokens(peak)}',
          ),
        ),
      ],
    );
  }
}

/// 按 Key：占比条 + 列表。
class _PerKeyBlock extends StatelessWidget {
  const _PerKeyBlock({required this.state, required this.usage});

  final AppState state;
  final Usage usage;

  @override
  Widget build(BuildContext context) {
    final sym = Fmt.currencySymbol(usage.currency);

    if (!usage.perKeyTracked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('按 Key', note: '本月'),
          DsPanel(
            padding: const EdgeInsets.all(12),
            child: Text(
              '分 Key 用量需要平台导出接口，当前不可用'
              '${usage.perKeyError == null ? '' : '（${usage.perKeyError!.hint}）'}。',
              style: DsText.hint,
            ),
          ),
        ],
      );
    }
    final keys = usage.perKey;
    if (keys.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('按 Key', note: '本月'),
          DsPanel(
            padding: const EdgeInsets.all(12),
            child: Text('本月没有按 Key 的调用记录。', style: DsText.hint),
          ),
        ],
      );
    }

    final total = state.perKeyCostSum <= 0 ? 1.0 : state.perKeyCostSum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('按 Key', note: '本月 · 合计 $sym${Fmt.money(total)}'),
        DsPanel(
          child: Column(
            children: [
              for (var i = 0; i < keys.length; i++) ...[
                if (i > 0) const Hairline(indent: 12, endIndent: 12),
                _KeyRow(entry: keys[i], total: total, sym: sym),
              ],
            ],
          ),
        ),
        if (keys.length > 1)
          const DsHint('余额为账户级，同账号所有 Key 共用一个余额；此处拆的是各自消耗。'),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.entry, required this.total, required this.sym});

  final KeyUsage entry;
  final double total;
  final String sym;

  @override
  Widget build(BuildContext context) {
    final share = (entry.month.cost / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  style: DsText.rowTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!entry.hasKey) ...[
                const StatusBadge(label: '未登记', color: DsColors.inkTertiary),
                const SizedBox(width: 8),
              ],
              Text(
                '$sym${Fmt.money(entry.month.cost)}',
                style: DsText.mono.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: DsColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ShareBar(segments: [(share, DsColors.primary)], height: 3),
          const SizedBox(height: 5),
          Text(
            '${Fmt.tokens(entry.month.tokens)} tokens · '
            '${Fmt.count(entry.month.requests)} 次 · '
            '今日 −${Fmt.money(entry.today.cost)}',
            style: DsText.rowSub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 按 Model：横向占比条 + 列表。
class _PerModelBlock extends StatelessWidget {
  const _PerModelBlock({required this.usage});

  final Usage usage;

  @override
  Widget build(BuildContext context) {
    if (usage.models.isEmpty) return const SizedBox.shrink();
    final sym = Fmt.currencySymbol(usage.currency);
    final palette = [DsColors.primary, DsColors.primaryHover];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('按 Model', note: '本月'),
        DsPanel(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            children: [
              ShareBar(
                segments: [
                  for (var i = 0; i < usage.models.length; i++)
                    (
                      usage.models[i].usage.tokens.toDouble(),
                      palette[i % palette.length]
                          .withValues(alpha: i == 0 ? 1.0 : 0.5),
                    ),
                ],
                height: 8,
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < usage.models.length; i++) ...[
                if (i > 0) const Hairline(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      StatusDot(
                        color: palette[i % palette.length]
                            .withValues(alpha: i == 0 ? 1.0 : 0.55),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              usage.models[i].model,
                              style: DsText.rowTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _modelSub(usage.models[i]),
                              style: DsText.rowSub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$sym${Fmt.money(usage.models[i].usage.cost)}',
                        style: DsText.mono
                            .copyWith(fontSize: 12.5, color: DsColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _modelSub(ModelUsage m) {
    final base = '${Fmt.tokens(m.usage.tokens)} tokens';
    final rate = m.usage.cacheHitRate;
    return rate == null
        ? base
        : '$base · 命中 ${(rate * 100).toStringAsFixed(1)}%';
  }
}

/// 凭据状态：列表 + 语义点，不再单独占一张卡。
class _CredentialBlock extends StatelessWidget {
  const _CredentialBlock({required this.snapshot});

  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final checks = snapshot.keyChecks;
    if (checks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('凭据状态'),
        DsPanel(
          child: Column(
            children: [
              for (var i = 0; i < checks.length; i++) ...[
                if (i > 0) const Hairline(indent: 12, endIndent: 12),
                DsRow(
                  leading: StatusDot(
                    color: checks[i].ok ? DsColors.success : DsColors.danger,
                  ),
                  title: checks[i].name,
                  sub: checks[i].masked,
                  subMono: true,
                  trailing: Text(
                    checks[i].ok ? '有效' : (checks[i].error?.hint ?? '失效'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: checks[i].ok ? DsColors.success : DsColors.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 用量接口失效时的就地提示：余额照常显示，不整页报错。
class _UsageErrorNotice extends StatelessWidget {
  const _UsageErrorNotice({required this.error, required this.onOpenSettings});

  final ApiIssue error;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return NoticeBar(
      title: '用量数据不可用',
      detail: '${error.hint}（${error.code}）。余额不受影响；'
          '在设置里重新填入平台 userToken 即可恢复。',
      color: DsColors.danger,
      actions: [
        FilledButton(onPressed: onOpenSettings, child: const Text('去设置')),
      ],
    );
  }
}

/// 首次使用：两步引导，不显示 0 元和空图表。
class _FirstRunGuide extends StatelessWidget {
  const _FirstRunGuide({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('还差两步', style: DsText.emptyTitle),
          const SizedBox(height: 6),
          const Text(
            '凭据只存在本机，直连 deepseek.com，不经任何中转。',
            style: TextStyle(fontSize: 12, height: 1.6, color: DsColors.inkSubtle),
          ),
          const SizedBox(height: 22),
          DsPanel(
            child: Column(
              children: [
                DsRow(
                  leading: const _StepBadge(step: 1, active: true),
                  title: '添加 API Key',
                  sub: '解锁余额与 Key 有效性',
                  trailing: Text(
                    '去添加',
                    style: TextStyle(fontSize: 11, color: DsColors.primaryHover),
                  ),
                  onTap: onOpenSettings,
                ),
                const Hairline(indent: 12, endIndent: 12),
                DsRow(
                  leading: const _StepBadge(step: 2, active: false),
                  title: '填入平台 userToken',
                  sub: '解锁 token 用量与分 Key 明细',
                  trailing: const Text(
                    '去填入',
                    style: TextStyle(fontSize: 11, color: DsColors.inkTertiary),
                  ),
                  onTap: onOpenSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '只想先看看界面？可在设置里打开「演示数据」，用虚构数字预览全部页面。',
            style: DsText.hint,
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.step, required this.active});

  final int step;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? DsColors.primary : DsColors.hairlineStrong;
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$step',
        style: TextStyle(
          fontSize: 9,
          color: active ? DsColors.primary : DsColors.inkTertiary,
        ),
      ),
    );
  }
}
