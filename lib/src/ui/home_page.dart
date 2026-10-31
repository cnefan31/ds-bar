import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'charts.dart';
import 'common.dart';

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
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: DsColors.primary),
        ),
      );
    }

    final needsSetup = config.keys.isEmpty && !config.demoMode;

    return RefreshIndicator(
      onRefresh: () => state.refresh(),
      color: DsColors.primary,
      backgroundColor: DsColors.surface2,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (config.keys.isEmpty && !config.demoMode) ...[
            NoticeBar(
              text: '还没有添加 API Key。添加后可读取余额；再填入平台 userToken 才能看到 token 用量。',
              action: TextButton(
                onPressed: onOpenSettings,
                child: const Text('去设置'),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (snapshot == null)
            DsCard(
              child: EmptyHint(
                text: needsSetup ? '先完成配置，再下拉或点右上角同步。' : '暂无数据，点右上角同步。',
                action: FilledButton(
                  onPressed: onOpenSettings,
                  child: const Text('打开设置'),
                ),
              ),
            )
          else ...[
            _BalanceSection(state: state, snapshot: snapshot),
            const SizedBox(height: 14),
            _TodaySection(state: state, snapshot: snapshot),
            const SizedBox(height: 14),
            _MonthSection(state: state, snapshot: snapshot),
            const SizedBox(height: 14),
            _PerKeySection(state: state, snapshot: snapshot),
            const SizedBox(height: 14),
            _PerModelSection(state: state, snapshot: snapshot),
            const SizedBox(height: 14),
            _KeyCheckSection(snapshot: snapshot),
            const SizedBox(height: 18),
            Center(
              child: Text(
                '更新于 ${Fmt.relativeTime(snapshot.fetchedAt)}',
                style: const TextStyle(fontSize: 11, color: DsColors.inkTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceSection extends StatelessWidget {
  const _BalanceSection({required this.state, required this.snapshot});

  final AppState state;
  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final balance = snapshot.balance;
    final info = balance?.primary;
    final sym = Fmt.currencySymbol(info?.currency ?? snapshot.currency);
    final available = balance?.isAvailable ?? false;

    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '账户余额',
                style: TextStyle(fontSize: 12, color: DsColors.inkSubtle),
              ),
              const Spacer(),
              if (snapshot.demo)
                const StatusBadge(label: '演示数据', color: DsColors.warning)
              else if (balance == null)
                StatusBadge(
                  label: snapshot.balanceError?.hint ?? '不可用',
                  color: DsColors.danger,
                )
              else
                StatusBadge(
                  label: available ? '可用' : '余额不足',
                  color: available ? DsColors.success : DsColors.danger,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                sym,
                style: const TextStyle(fontSize: 20, color: DsColors.inkSubtle, height: 1),
              ),
              const SizedBox(width: 3),
              Text(
                info == null ? '--' : Fmt.moneyExact(info.totalBalance),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.6,
                  color: DsColors.ink,
                  height: 1.05,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (info != null)
            Text(
              '充值 $sym${Fmt.moneyExact(info.toppedUpBalance)} · 赠送 $sym${Fmt.moneyExact(info.grantedBalance)}',
              style: const TextStyle(fontSize: 12, color: DsColors.inkSubtle),
            ),
          const SizedBox(height: 14),
          const Hairline(),
          const SizedBox(height: 6),
          if (snapshot.balanceError != null && balance == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${snapshot.balanceError!.hint}：${snapshot.balanceError!.message}',
                style: const TextStyle(fontSize: 11.5, color: DsColors.danger, height: 1.5),
              ),
            )
          else ...[
            StatRow(
              label: '本月消费',
              value: '${Fmt.currencySymbol(snapshot.currency)}${Fmt.moneyExact(snapshot.usage?.monthTotal.cost ?? 0)}',
            ),
            StatRow(
              label: '本月 token',
              value: Fmt.tokens(snapshot.usage?.monthTotal.tokens ?? 0),
              sub: snapshot.usage?.monthTotal.requests != null
                  ? '${Fmt.count(snapshot.usage!.monthTotal.requests)} 次请求'
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.state, required this.snapshot});

  final AppState state;
  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final usage = snapshot.usage;
    if (usage == null) {
      return DsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('今日与本月用量', style: TextStyle(fontSize: 13, color: DsColors.ink)),
            const SizedBox(height: 8),
            NoticeBar(
              text: snapshot.usageError != null
                  ? '用量不可用：${snapshot.usageError!.hint}'
                  : '未配置平台 userToken',
              color: DsColors.warning,
            ),
            const SizedBox(height: 8),
            const Text(
              '余额来自官方 API；token 用量来自开放平台网页接口，需要在设置里填入 userToken。',
              style: TextStyle(fontSize: 11.5, color: DsColors.inkSubtle, height: 1.55),
            ),
          ],
        ),
      );
    }
    final today = usage.today;
    final sym = Fmt.currencySymbol(usage.currency);
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('今日', style: TextStyle(fontSize: 12, color: DsColors.inkSubtle)),
              const Spacer(),
              if (usage.todayError != null)
                StatusBadge(label: usage.todayError!.hint, color: DsColors.warning),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Metric(
                value: today == null ? '--' : sym + Fmt.money(today.cost),
                label: '消费',
              ),
              _Metric(
                value: today == null ? '--' : Fmt.tokens(today.tokens),
                label: 'tokens',
              ),
              _Metric(
                value: today == null ? '--' : Fmt.count(today.requests),
                label: '请求',
              ),
            ],
          ),
          if (today != null) ...[
            const SizedBox(height: 14),
            CompositionBar(bucket: today),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: DsTheme.mono.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.4,
              color: DsColors.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11, color: DsColors.inkSubtle)),
        ],
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({required this.state, required this.snapshot});

  final AppState state;
  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final usage = snapshot.usage;
    if (usage == null || usage.days.isEmpty) return const SizedBox.shrink();
    final sym = Fmt.currencySymbol(usage.currency);
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            '${Fmt.monthLabel(usage.year, usage.month)} 每日用量',
            trailing: Text(
              '${Fmt.count(usage.monthTotal.requests)} 次 · $sym${Fmt.money(usage.monthTotal.cost)}',
              style: const TextStyle(fontSize: 11, color: DsColors.inkSubtle),
            ),
          ),
          DailyBarChart(days: usage.days),
        ],
      ),
    );
  }
}

class _PerKeySection extends StatelessWidget {
  const _PerKeySection({required this.state, required this.snapshot});

  final AppState state;
  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final usage = snapshot.usage;
    if (usage == null) return const SizedBox.shrink();
    final sym = Fmt.currencySymbol(usage.currency);
    final keys = usage.perKey;

    if (!usage.perKeyTracked) {
      return DsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('按 API Key'),
            NoticeBar(
              text: '分 key 用量需要导出接口，当前不可用'
                  '${usage.perKeyError == null ? '' : '（${usage.perKeyError!.hint}）'}。',
              color: DsColors.inkSubtle,
            ),
          ],
        ),
      );
    }

    if (keys.isEmpty) {
      return DsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('按 API Key'),
            const EmptyHint(text: '本月没有按 key 的调用记录。'),
          ],
        ),
      );
    }

    return DsCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            '按 API Key · 本月',
            trailing: Text(
              '合计 $sym${Fmt.money(state.perKeyCostSum)}',
              style: const TextStyle(fontSize: 11, color: DsColors.inkSubtle),
            ),
          ),
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const Hairline(),
            _KeyRow(keyUsage: keys[i], sym: sym),
          ],
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.keyUsage, required this.sym});

  final KeyUsage keyUsage;
  final String sym;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        keyUsage.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: DsColors.ink,
                        ),
                      ),
                    ),
                    if (!keyUsage.hasKey) ...[
                      const SizedBox(width: 6),
                      const StatusBadge(label: '未登记', color: DsColors.inkTertiary),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$sym${Fmt.money(keyUsage.month.cost)}',
                style: DsTheme.mono.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: DsColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                '${Fmt.tokens(keyUsage.month.tokens)} tokens',
                style: const TextStyle(fontSize: 11.5, color: DsColors.inkSubtle),
              ),
              const SizedBox(width: 10),
              Text(
                '${Fmt.count(keyUsage.month.requests)} 次',
                style: const TextStyle(fontSize: 11.5, color: DsColors.inkSubtle),
              ),
              const SizedBox(width: 10),
              Text(
                '今日 $sym${Fmt.money(keyUsage.today.cost)}',
                style: const TextStyle(fontSize: 11.5, color: DsColors.inkTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerModelSection extends StatelessWidget {
  const _PerModelSection({required this.state, required this.snapshot});

  final AppState state;
  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final usage = snapshot.usage;
    if (usage == null || usage.models.isEmpty) return const SizedBox.shrink();
    final sym = Fmt.currencySymbol(usage.currency);
    final total = usage.monthTotal.tokens;
    return DsCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('按模型 · 本月'),
          for (var i = 0; i < usage.models.length; i++) ...[
            if (i > 0) const Hairline(),
            _ModelRow(model: usage.models[i], sym: sym, totalTokens: total),
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.sym, required this.totalTokens});

  final ModelUsage model;
  final String sym;
  final int totalTokens;

  @override
  Widget build(BuildContext context) {
    final share = totalTokens <= 0 ? 0.0 : model.usage.tokens / totalTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model.model,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: DsColors.ink,
                  ),
                ),
              ),
              Text(
                '$sym${Fmt.money(model.usage.cost)}',
                style: DsTheme.mono.copyWith(fontSize: 12.5, color: DsColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: DsColors.surface3,
              valueColor: const AlwaysStoppedAnimation(DsColors.primary),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${Fmt.tokens(model.usage.tokens)} tokens · ${(share * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 11, color: DsColors.inkSubtle),
              ),
              const Spacer(),
              if (model.usage.cacheHitRate != null)
                Text(
                  '命中 ${(model.usage.cacheHitRate! * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11, color: DsColors.inkTertiary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyCheckSection extends StatelessWidget {
  const _KeyCheckSection({required this.snapshot});

  final Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final checks = snapshot.keyChecks;
    if (checks.isEmpty) return const SizedBox.shrink();
    return DsCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('已配置 Key 状态'),
          for (var i = 0; i < checks.length; i++) ...[
            if (i > 0) const Hairline(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          checks[i].name,
                          style: const TextStyle(fontSize: 13, color: DsColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          checks[i].masked,
                          style: DsTheme.mono.copyWith(
                            fontSize: 11,
                            color: DsColors.inkTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: checks[i].ok ? '有效' : (checks[i].error?.hint ?? '无效'),
                    color: checks[i].ok ? DsColors.success : DsColors.danger,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            '余额是账户级数据，同一账号下的 key 共享同一个余额。',
            style: TextStyle(fontSize: 11, color: DsColors.inkTertiary, height: 1.5),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
