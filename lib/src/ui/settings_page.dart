import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../native_bridge.dart';
import '../theme.dart';
import 'common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state, required this.bridge});

  final AppState state;
  final NativeBridge bridge;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _tokenCtrl;
  late TextEditingController _cookieCtrl;
  bool _saving = false;
  bool _tokenVisible = false;

  /// 拖动中临时值，松手后写回配置。
  int? _dragMinutes;

  @override
  void initState() {
    super.initState();
    // 出于安全考虑不回显已保存的 token，仅显示占位提示。
    _tokenCtrl = TextEditingController();
    _cookieCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _cookieCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials() async {
    setState(() => _saving = true);
    await widget.state.updateSettings(
      userToken: _tokenCtrl.text.trim().isEmpty ? null : _tokenCtrl.text.trim(),
      cookie: _cookieCtrl.text.trim().isEmpty ? null : _cookieCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _tokenCtrl.clear();
    _cookieCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存凭据')),
    );
  }

  Future<void> _addKey() async {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DsColors.canvas,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '添加 API Key',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: DsColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              '名称只是本地别名，建议与平台「按 API Key」列表里的名称保持一致，用量才能对上。',
              style: TextStyle(fontSize: 12, color: DsColors.inkSubtle, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '名称'),
              style: const TextStyle(fontSize: 13, color: DsColors.ink),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'sk- 开头的 API Key'),
              style: const TextStyle(fontSize: 13, color: DsColors.ink),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('保存'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (result == true) {
      final name = nameCtrl.text.trim();
      final key = keyCtrl.text.trim();
      if (key.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('API Key 不能为空')),
          );
        }
      } else {
        final fallback = 'key ${widget.state.config.keys.length + 1}';
        final config = await widget.bridge.appendKey(
          name: name.isEmpty ? fallback : name,
          key: key,
        );
        widget.state.replaceConfig(config);
        if (mounted) setState(() {});
      }
    }
    nameCtrl.dispose();
    keyCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.state.config;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ---------- 凭据 ----------
        const SectionLabel('凭据'),
        DsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '平台 userToken',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: DsColors.ink),
                    ),
                  ),
                  StatusBadge(
                    label: config.userTokenSet ? '已配置' : '未配置',
                    color: config.userTokenSet ? DsColors.success : DsColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '用于读取 token 用量与消费明细。获取方式：浏览器登录 platform.deepseek.com → F12 → '
                'Application → Local Storage → 复制 userToken 的值。',
                style: TextStyle(fontSize: 11.5, color: DsColors.inkSubtle, height: 1.6),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenCtrl,
                obscureText: !_tokenVisible,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: config.userTokenSet ? '已保存，粘贴新值可覆盖' : '粘贴 userToken',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _tokenVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: DsColors.inkSubtle,
                    ),
                    onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
                  ),
                ),
                style: const TextStyle(fontSize: 13, color: DsColors.ink),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cookieCtrl,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: config.cookieSet ? 'Cookie 已保存，可留空' : 'Cookie（可选，token 失效时补上）',
                ),
                style: const TextStyle(fontSize: 12, color: DsColors.ink),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _saveCredentials,
                      child: Text(_saving ? '保存中…' : '保存凭据'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => widget.bridge.openUrl('https://platform.deepseek.com/usage'),
                    child: const Text('打开平台'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ---------- API Keys ----------
        SectionLabel(
          'API Keys',
          trailing: TextButton.icon(
            onPressed: _addKey,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加'),
          ),
        ),
        DsCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: config.keys.isEmpty
              ? const EmptyHint(text: '还没有 API Key。余额查询需要一个有效 key。')
              : Column(
                  children: [
                    for (var i = 0; i < config.keys.length; i++) ...[
                      if (i > 0) const Hairline(),
                      _KeyTile(
                        entry: config.keys[i],
                        onDelete: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: DsColors.surface2,
                              title: const Text('删除这个 key？', style: TextStyle(fontSize: 16, color: DsColors.ink)),
                              content: Text(
                                '「${config.keys[i].name}」将从本机移除，不影响平台上的 key。',
                                style: const TextStyle(fontSize: 13, color: DsColors.inkMuted, height: 1.5),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('删除', style: TextStyle(color: DsColors.danger)),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            final result = await widget.bridge.removeKey(config.keys[i].id);
                            widget.state.replaceConfig(result);
                            if (mounted) setState(() {});
                          }
                        },
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 8),
        const Text(
          '余额是账户级数据，同一账号下所有 key 共享同一个余额；分 key 的 token 用量按平台侧 key 名称匹配。',
          style: TextStyle(fontSize: 11, color: DsColors.inkTertiary, height: 1.55),
        ),
        const SizedBox(height: 20),

        // ---------- 通知与磁贴 ----------
        const SectionLabel('通知栏与磁贴'),
        DsCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('通知栏常驻余额', style: TextStyle(fontSize: 13.5, color: DsColors.ink)),
                subtitle: const Text(
                  '下拉通知栏可见余额、今日消费与本月消费',
                  style: TextStyle(fontSize: 11.5, color: DsColors.inkSubtle),
                ),
                value: config.notifyEnabled,
                onChanged: (v) async {
                  await widget.state.updateSettings(notifyEnabled: v);
                  if (v) await widget.bridge.requestNotificationPermission();
                  if (mounted) setState(() {});
                },
              ),
              const Hairline(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('快速设置磁贴', style: TextStyle(fontSize: 13.5, color: DsColors.ink)),
                subtitle: const Text(
                  '在快捷开关面板显示余额，点按刷新',
                  style: TextStyle(fontSize: 11.5, color: DsColors.inkSubtle),
                ),
                value: config.tileEnabled,
                onChanged: (v) async {
                  await widget.state.updateSettings(tileEnabled: v);
                  if (mounted) setState(() {});
                },
              ),
              if (config.tileEnabled) ...[
                const Hairline(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('添加到快捷面板', style: TextStyle(fontSize: 13.5, color: DsColors.ink)),
                  subtitle: const Text(
                    '打开系统快捷设置编辑页，把 DeepSeek 余额拖入面板',
                    style: TextStyle(fontSize: 11.5, color: DsColors.inkSubtle),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: DsColors.inkTertiary),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await widget.bridge.openQsTileSettings();
                    if (!ok) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('无法直接打开，请手动编辑快捷设置面板')),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ---------- 刷新 ----------
        const SectionLabel('刷新'),
        DsCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('自动刷新间隔', style: TextStyle(fontSize: 13.5, color: DsColors.ink)),
                  ),
                  Text(
                    '${_dragMinutes ?? config.refreshMinutes} 分钟',
                    style: DsTheme.mono.copyWith(fontSize: 13, color: DsColors.inkMuted),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: DsColors.primary,
                  inactiveTrackColor: DsColors.surface3,
                  thumbColor: DsColors.ink,
                  overlayColor: DsColors.primary.withValues(alpha: 0.12),
                  trackHeight: 2,
                ),
                child: Slider(
                  value: (_dragMinutes ?? _clampMinutes(config.refreshMinutes)).toDouble(),
                  min: 15,
                  max: 360,
                  divisions: 23,
                  onChanged: (v) => setState(() => _dragMinutes = v.round()),
                  onChangeEnd: (v) async {
                    setState(() => _dragMinutes = null);
                    await widget.state.updateSettings(refreshMinutes: v.round());
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const Text(
                '后台刷新由系统调度，实际间隔可能被系统延后以省电（最短 15 分钟）。',
                style: TextStyle(fontSize: 11, color: DsColors.inkTertiary, height: 1.5),
              ),
              const SizedBox(height: 12),
              const Hairline(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('演示数据', style: TextStyle(fontSize: 13.5, color: DsColors.ink)),
                subtitle: const Text(
                  '用虚构数字预览界面，不代表真实账户',
                  style: TextStyle(fontSize: 11.5, color: DsColors.inkSubtle),
                ),
                value: config.demoMode,
                onChanged: (v) async {
                  await widget.state.updateSettings(demoMode: v);
                  await widget.state.refresh(silent: true);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ---------- 关于 ----------
        const SectionLabel('数据来源'),
        DsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SourceRow(
                title: '账户余额',
                endpoint: 'api.deepseek.com/user/balance',
                note: '官方公开接口，用 API Key 鉴权',
                stable: true,
              ),
              const Hairline(),
              _SourceRow(
                title: 'token 用量 / 消费',
                endpoint: 'platform.deepseek.com/api/v0/usage/*',
                note: '开放平台网页接口，需 userToken，非官方公开 API',
                stable: false,
              ),
              const Hairline(),
              _SourceRow(
                title: '分 key 明细',
                endpoint: 'platform.deepseek.com/api/v0/usage/export',
                note: '导出 CSV，按 key 名称聚合',
                stable: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '凭据只保存在本机应用私有存储，不上传任何第三方服务器。所有请求由手机直接发往 deepseek.com。',
          style: TextStyle(fontSize: 11, color: DsColors.inkTertiary, height: 1.55),
        ),
      ],
    );
  }

  int _clampMinutes(int v) => v.clamp(15, 360);
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.entry, required this.onDelete});

  final ConfiguredKey entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.name,
              style: const TextStyle(fontSize: 13, color: DsColors.ink),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18, color: DsColors.inkTertiary),
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.title,
    required this.endpoint,
    required this.note,
    required this.stable,
  });

  final String title;
  final String endpoint;
  final String note;
  final bool stable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: DsColors.ink,
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                label: stable ? '稳定' : '可能变更',
                color: stable ? DsColors.success : DsColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            endpoint,
            style: DsTheme.mono.copyWith(fontSize: 11, color: DsColors.inkSubtle),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: const TextStyle(fontSize: 11, color: DsColors.inkTertiary, height: 1.5),
          ),
        ],
      ),
    );
  }
}
