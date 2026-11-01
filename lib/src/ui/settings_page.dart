import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../format.dart';
import '../native_bridge.dart';
import '../theme.dart';
import 'common.dart';

/// 设置页。
///
/// 结构按「解锁什么」组织，而不是按数据类型平铺：
///  1. 连接状态 —— 一眼看出哪部分可用
///  2. 平台会话 —— 解锁用量（userToken）
///  3. API Key —— 解锁余额
///  4. 刷新 —— 间隔 + 通知 + 磁贴
///  5. 显示 —— 演示数据
///  6. 数据来源 —— 接口与稳定性标注
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state, required this.bridge});

  final AppState state;
  final NativeBridge bridge;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _tokenCtrl = TextEditingController();
  final _cookieCtrl = TextEditingController();

  bool _saving = false;
  bool _tokenVisible = false;
  bool _testing = false;
  int? _dragMinutes;
  ProbeResult? _probe;
  LoginSnapshot? _login;
  bool _loginBusy = false;
  Timer? _loginPoll;

  /// 刷新间隔预设档位。滑块的 23 个刻度实际只有这几档有意义。
  static const _intervals = [15, 30, 60, 360];

  @override
  void initState() {
    super.initState();
    // 进页面时同步一次登录状态，避免切走后回来显示过期信息。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLoginState());
  }

  Future<void> _syncLoginState() async {
    final snap = await widget.bridge.getLoginState();
    if (!mounted) return;
    setState(() => _login = snap);
    if (snap.isBusy) _startLoginPoll();
  }

  void _startLoginPoll() {
    _loginPoll?.cancel();
    // 2 秒一次。登录是短流程，轮询足够，且不引入 event channel 的复杂度。
    _loginPoll = Timer.periodic(const Duration(seconds: 2), (t) async {
      final snap = await widget.bridge.getLoginState();
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _login = snap);
      if (!snap.isBusy) {
        t.cancel();
        if (snap.isDone) await widget.state.load();
      }
    });
  }

  Future<void> _startBrowserLogin() async {
    if (_loginBusy) return;
    setState(() => _loginBusy = true);
    try {
      final snap = await widget.bridge.startBrowserLogin();
      if (!mounted) return;
      setState(() => _login = snap);
      _startLoginPoll();
    } finally {
      if (mounted) setState(() => _loginBusy = false);
    }
  }

  Future<void> _cancelBrowserLogin() async {
    final snap = await widget.bridge.cancelBrowserLogin();
    if (!mounted) return;
    _loginPoll?.cancel();
    setState(() => _login = snap);
  }

  Future<void> _signOutPlatform() async {
    final snap = await widget.bridge.signOutPlatform();
    if (!mounted) return;
    setState(() => _login = snap);
    await widget.state.load();
  }

  @override
  void dispose() {
    _loginPoll?.cancel();
    _tokenCtrl.dispose();
    _cookieCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials() async {
    final token = _tokenCtrl.text.trim();
    final cookie = _cookieCtrl.text.trim();
    if (token.isEmpty && cookie.isEmpty) {
      _toast('没有需要保存的内容');
      return;
    }
    setState(() => _saving = true);
    await widget.state.updateSettings(
      userToken: token.isEmpty ? null : token,
      cookie: cookie.isEmpty ? null : cookie,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _tokenCtrl.clear();
    _cookieCtrl.clear();
    _toast('已保存凭据');
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    final result = await widget.bridge.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
    });
    if (result == null) {
      _toast('测试失败：通道不可用');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DsColors.canvas,
      builder: (ctx) => _ProbeSheet(result: result),
    );
  }

  Future<void> _addKey() async {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
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
            const Text('添加 API Key', style: DsText.emptyTitle),
            const SizedBox(height: 6),
            const Text(
              '名称只是本地别名，建议与平台「按 API Key」列表保持一致，用量才能对上。',
              style: TextStyle(fontSize: 12, height: 1.55, color: DsColors.inkSubtle),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(fontSize: 13, color: DsColors.ink),
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontSize: 13, color: DsColors.ink),
              decoration: const InputDecoration(labelText: 'sk- 开头的 API Key'),
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
    if (ok == true) {
      final key = keyCtrl.text.trim();
      if (key.isEmpty) {
        _toast('API Key 不能为空');
      } else {
        final name = nameCtrl.text.trim();
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

  Future<void> _confirmRemoveKey(ConfiguredKey entry) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DsColors.surface2,
        title: Text('删除 ${entry.name}', style: const TextStyle(fontSize: 16, color: DsColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '仅从本机移除，不影响平台上的 Key。',
              style: TextStyle(fontSize: 12, height: 1.5, color: DsColors.inkMuted),
            ),
            const SizedBox(height: 8),
            Text(
              '请确认这是 ${entry.masked.isEmpty ? entry.name : entry.masked}',
              style: DsText.rowSub.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: DsColors.danger)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (ok == true) {
      final config = await widget.bridge.removeKey(entry.id);
      widget.state.replaceConfig(config);
      if (mounted) setState(() {});
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.state.config;
    final snapshot = widget.state.snapshot;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DsSpace.screenH,
        8,
        DsSpace.screenH,
        40,
      ),
      children: [
        _connectionSection(config, snapshot),
        const SectionHeader('平台会话', note: '解锁用量'),
        _platformSession(config),
        SectionHeader(
          'API Key',
          note: '解锁余额',
          action: TextButton.icon(
            onPressed: _addKey,
            icon: const Icon(Icons.add, size: 15),
            label: const Text('添加'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        _keyList(config),
        _platformKeysSection(),
        const SectionHeader('刷新'),
        _refreshSection(config),
        const SectionHeader('通知与磁贴'),
        _notifySection(config),
        const SectionHeader('显示'),
        _displaySection(config),
        const SectionHeader('数据来源'),
        _sourcesSection(),
        const SizedBox(height: 16),
        Text(
          '凭据只保存在本机应用私有存储，不上传任何第三方服务器。'
          '所有请求由手机直连 deepseek.com。',
          style: DsText.hint,
        ),
      ],
    );
  }

  /// 连接状态：余额与用量两块，各自语义点 + 一句人话。
  Widget _connectionSection(AppConfig config, Snapshot? snapshot) {
    final balanceOk = snapshot?.balance != null;
    final usageOk = snapshot?.usage != null;
    final balanceIssue = snapshot?.balanceError;
    final usageIssue = snapshot?.usageError;

    // 余额有两条路：官方接口（需 API Key）与平台账户摘要（登录态即可）。
    // 所以判断依据必须是「有没有拿到余额」，而不是「有没有填 API Key」。
    final platformBalance = snapshot?.balanceSource == 'platform';
    String balanceText;
    if (balanceOk) {
      balanceText = platformBalance
          ? '已连接 · 平台账户'
          : '已连接 · ${config.keys.length} 个 Key';
    } else if (config.keys.isEmpty && !config.userTokenSet) {
      balanceText = '未添加 API Key';
    } else {
      balanceText = balanceIssue?.hint ?? '获取失败';
    }

    String usageText;
    if (!config.userTokenSet) {
      usageText = '未配置 userToken';
    } else if (usageOk) {
      usageText = '已连接';
    } else {
      usageText = usageIssue?.hint ?? '获取失败';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('连接状态', topSpace: false),
        DsPanel(
          child: Column(
            children: [
              DsRow(
                leading: StatusDot(
                  color: balanceOk
                      ? DsColors.success
                      : (config.keys.isEmpty && !config.userTokenSet
                          ? DsColors.inkTertiary
                          : DsColors.danger),
                ),
                title: '余额',
                sub: balanceText,
                trailing: StatusBadge(
                  label: balanceOk ? '正常' : '需处理',
                  color: balanceOk ? DsColors.success : DsColors.danger,
                ),
              ),
              const Hairline(indent: 12, endIndent: 12),
              DsRow(
                leading: StatusDot(
                  color: usageOk
                      ? DsColors.success
                      : (config.userTokenSet ? DsColors.danger : DsColors.inkTertiary),
                ),
                title: '用量与消费',
                sub: usageText,
                trailing: StatusBadge(
                  label: usageOk ? '正常' : '需处理',
                  color: usageOk ? DsColors.success : DsColors.danger,
                ),
              ),
            ],
          ),
        ),
        const DsHint('浏览器授权后，余额、用量与 Key 列表都走平台账号，无需 API Key；'
            '手动填 userToken 或添加 API Key 是备用路径，两者互不影响。'),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton(
              onPressed: _testing ? null : _testConnection,
              child: Text(_testing ? '测试中…' : '测试连接'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => widget.bridge.openUrl('https://platform.deepseek.com/usage'),
              child: const Text('打开平台'),
            ),
          ],
        ),
        if (_probe != null) ...[
          const SizedBox(height: 8),
          Text(
            '上次测试：${_probe!.okCount} 项通过，${_probe!.failCount} 项失败',
            style: DsText.hint,
          ),
        ],
      ],
    );
  }

  /// 平台会话：userToken 状态 + 输入 + 操作。
  Widget _platformSession(AppConfig config) {
    // 四态：未连接 / 等待中 / 已连接 / 失败。
    // 手动填 userToken 的那条路始终保留，折叠在下方，登录失败时是唯一退路。
    final login = _login;
    final connected = config.userTokenSet;
    final waiting = login?.isBusy ?? false;
    final failed = login?.isFailed ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsPanel(
          child: Column(
            children: [
              DsRow(
                leading: StatusDot(
                  color: waiting
                      ? DsColors.primary
                      : connected
                          ? DsColors.success
                          : failed
                              ? DsColors.danger
                              : DsColors.inkTertiary,
                ),
                title: waiting ? '正在登录' : connected ? '已连接' : failed ? '登录未完成' : '用量与消费',
                sub: waiting
                    ? '在浏览器里完成登录后会自动回来'
                    : connected
                        ? (config.loginMethod == 'browser' ? '浏览器授权' : '手动配置')
                        : failed
                            ? (login?.errorMessage ?? '未拿到凭据')
                            : '用 DeepSeek 账号登录后解锁',
                trailing: StatusBadge(
                  label: waiting ? '等待' : connected ? '已连接' : '未连接',
                  color: waiting
                      ? DsColors.primary
                      : connected
                          ? DsColors.success
                          : failed
                              ? DsColors.danger
                              : DsColors.warning,
                ),
              ),
              if (config.accountHint.isNotEmpty) ...[
                const Hairline(indent: 12, endIndent: 12),
                DsRow(
                  title: '账号',
                  sub: config.accountHint,
                ),
              ],
              if (waiting) ...[
                const Hairline(indent: 12, endIndent: 12),
                _loginWaitBody(login!),
              ],
              const Hairline(indent: 12, endIndent: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  children: [
                    if (!connected && !waiting)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loginBusy ? null : _startBrowserLogin,
                          icon: const Icon(Icons.open_in_browser, size: 16),
                          label: Text(failed ? '重试浏览器登录' : '用浏览器登录'),
                        ),
                      ),
                    if (connected)
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _loginBusy ? null : _signOutPlatform,
                          child: const Text('退出登录'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!connected && !waiting)
          const DsHint(
            '会跳到系统浏览器。若浏览器里已登录 DeepSeek，点一下授权就回到 App；'
            '没登录会先让你登录。授权链接 10 分钟内有效。',
          ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: DsSpace.tight),
            child: Text(
              '登录失败不影响余额：API Key 那条路照常工作。也可以直接用下面的手动方式。',
              style: DsText.hint.copyWith(color: DsColors.warning),
            ),
          ),
        const SizedBox(height: 8),
        // 手动入口：默认折叠，登录不可用时是唯一退路，所以必须有。
        _manualTokenSection(config),
      ],
    );
  }

  Widget _loginWaitBody(LoginSnapshot login) {
    final left = login.remainingSeconds(DateTime.now());
    final mm = (left ~/ 60).toString();
    final ss = (left % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LoginStep(index: 1, title: '浏览器已打开授权页', sub: '没自动跳过去就再点一次'),
          _LoginStep(index: 2, title: '登录并点「授权」', sub: '已登录的账号会直接显示确认页'),
          _LoginStep(index: 3, title: '自动回到这里', sub: '不用手动切回来', last: true),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: login.authorizeUrl.isEmpty
                      ? null
                      : () => widget.bridge.openUrl(login.authorizeUrl),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 34),
                    textStyle: DsText.rowTitle,
                  ),
                  child: const Text('再打开浏览器'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: _cancelBrowserLogin,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 34),
                    textStyle: DsText.rowTitle,
                  ),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
          if (left > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('链接 $mm:$ss 后失效', style: DsText.hint),
            ),
        ],
      ),
    );
  }

  Widget _manualTokenSection(AppConfig config) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: Text('手动填 userToken', style: DsText.rowTitle),
        subtitle: Text(
          config.userTokenSet ? '已配置，可覆盖' : '浏览器登录不可用时用这个',
          style: DsText.rowSub,
        ),
        iconColor: DsColors.inkSubtle,
        collapsedIconColor: DsColors.inkSubtle,
        children: [
          DsPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _tokenCtrl,
                    obscureText: !_tokenVisible,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DsColors.ink,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: config.userTokenSet ? '已保存，粘贴新值可覆盖' : '粘贴 userToken',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _tokenVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 17,
                          color: DsColors.inkSubtle,
                        ),
                        onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cookieCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 2,
                    minLines: 1,
                    style: const TextStyle(fontSize: 11, color: DsColors.ink),
                    decoration: InputDecoration(
                      hintText: config.cookieSet ? 'Cookie 已保存，可留空' : 'Cookie（可选）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _saveCredentials,
                      child: Text(_saving ? '保存中…' : '保存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const DsHint(
            '从 platform.deepseek.com 登录后，F12 → Application → Local Storage 复制 userToken。'
            '若接口返回非 JSON，补上同域 Cookie 再试。',
          ),
        ],
      ),
    );
  }

  Widget _keyList(AppConfig config) {
    if (config.keys.isEmpty) {
      return DsPanel(
        padding: const EdgeInsets.all(12),
        child: Text('还没有 API Key。余额查询需要一个有效 Key。', style: DsText.hint),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsPanel(
          child: Column(
            children: [
              for (var i = 0; i < config.keys.length; i++) ...[
                if (i > 0) const Hairline(indent: 12, endIndent: 12),
                DsRow(
                  leading: const StatusDot(color: DsColors.success),
                  title: config.keys[i].name,
                  sub: config.keys[i].masked,
                  subMono: true,
                  trailing: IconButton(
                    onPressed: () => _confirmRemoveKey(config.keys[i]),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 17,
                      color: DsColors.inkTertiary,
                    ),
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
        ),
        const DsHint('余额是账户级，同账号所有 Key 共用一个余额；分开填只是便于按 Key 对账。'),
      ],
    );
  }

  /// 平台侧自动发现的 Key 列表（浏览器登录后才有）。
  ///
  /// 平台不返回明文密钥，所以这里只做展示：名称、打码值、最后使用时间。
  /// 想用它查余额仍需在平台上另建 key 再填到上面——但登录态本身已经能拿余额，
  /// 所以多数时候不需要。
  Widget _platformKeysSection() {
    final snapshot = widget.state.snapshot;
    final keys = snapshot?.platformKeys ?? const <PlatformKey>[];
    if (keys.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('平台 Key', note: '登录后自动同步'),
        DsPanel(
          child: Column(
            children: [
              for (var i = 0; i < keys.length; i++) ...[
                if (i > 0) const Hairline(indent: 12, endIndent: 12),
                DsRow(
                  leading: StatusDot(color: DsColors.primary),
                  title: keys[i].name.isEmpty ? '（未命名）' : keys[i].name,
                  sub: _platformKeySub(keys[i]),
                ),
              ],
            ],
          ),
        ),
        const DsHint('这些 Key 直接来自 DeepSeek 账号，只读。平台不提供明文密钥，故不能用于官方余额接口。'),
      ],
    );
  }

  String _platformKeySub(PlatformKey k) {
    final parts = <String>[];
    if (k.masked.isNotEmpty) parts.add(k.masked);
    if (k.lastUse != null) {
      parts.add('最后使用 ${Fmt.relativeTime(k.lastUse!)}');
    } else {
      parts.add('从未使用');
    }
    return parts.join(' · ');
  }

  Widget _refreshSection(AppConfig config) {
    final current = _dragMinutes ?? config.refreshMinutes;
    // 落在某一档上就高亮那一档；否则归到最接近的一档。
    final selected = _intervals.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsPanel(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('后台自动刷新', style: DsText.rowTitle),
                        const Spacer(),
                        Text(
                          '每 ${_label(config.refreshMinutes)}',
                          style: DsText.rowSub.copyWith(color: DsColors.inkSubtle),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    _Segmented(
                      values: _intervals,
                      selected: selected,
                      labelOf: _label,
                      onSelected: (v) async {
                        setState(() => _dragMinutes = null);
                        await widget.state.updateSettings(refreshMinutes: v);
                        if (mounted) setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '系统省电策略可能推迟实际执行时间；这是系统行为，App 无法绕过。',
                      style: DsText.hint,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _label(int minutes) {
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      return '$h 小时';
    }
    return '$minutes 分钟';
  }

  Widget _notifySection(AppConfig config) {
    return DsPanel(
      child: Column(
        children: [
          _SwitchRow(
            title: '下拉通知栏显示余额',
            sub: '折叠一行两个数，展开四项指标',
            value: config.notifyEnabled,
            onChanged: (v) async {
              await widget.state.updateSettings(notifyEnabled: v);
              if (v) await widget.bridge.requestNotificationPermission();
              if (mounted) setState(() {});
            },
          ),
          const Hairline(indent: 12, endIndent: 12),
          _SwitchRow(
            title: '快捷设置磁贴',
            sub: '面板显示余额，点按刷新',
            value: config.tileEnabled,
            onChanged: (v) async {
              await widget.state.updateSettings(tileEnabled: v);
              if (mounted) setState(() {});
            },
          ),
          if (config.tileEnabled) ...[
            const Hairline(indent: 12, endIndent: 12),
            DsRow(
              title: '把磁贴加入面板',
              sub: '打开系统快捷设置编辑页',
              trailing: const Icon(
                Icons.chevron_right,
                size: 17,
                color: DsColors.inkTertiary,
              ),
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
    );
  }

  Widget _displaySection(AppConfig config) {
    return DsPanel(
      child: _SwitchRow(
        title: '演示数据',
        sub: '用虚构数字预览全部页面，不代表真实账户',
        value: config.demoMode,
        onChanged: (v) async {
          await widget.state.updateSettings(demoMode: v);
          await widget.state.refresh(silent: true);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _sourcesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsPanel(
          child: Column(
            children: [
              const DsRow(
                title: '账户余额',
                sub: 'api.deepseek.com/user/balance',
                subMono: true,
                trailing: StatusBadge(label: '官方', color: DsColors.success),
              ),
              const Hairline(indent: 12, endIndent: 12),
              const DsRow(
                title: '用量与消费',
                sub: 'platform.deepseek.com/api/v0/usage',
                subMono: true,
                trailing: StatusBadge(label: '网页接口', color: DsColors.warning),
              ),
              const Hairline(indent: 12, endIndent: 12),
              const DsRow(
                title: '分 Key 明细',
                sub: '…/usage/export',
                subMono: true,
                trailing: StatusBadge(label: '网页接口', color: DsColors.warning),
              ),
            ],
          ),
        ),
        const DsHint(
          '标「网页接口」的两项非官方公开 API，DeepSeek 改版可能失效；失效时余额不受影响。',
        ),
      ],
    );
  }
}

/// 分段控件：点选即生效，取代刻度过多的滑块。
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DsColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(values[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: values[i] == selected
                        ? DsColors.surface3
                        : DsColors.surface1,
                    border: i == 0
                        ? null
                        : const Border(
                            left: BorderSide(color: DsColors.hairline),
                          ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labelOf(values[i]),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: values[i] == selected
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: values[i] == selected
                          ? DsColors.ink
                          : DsColors.inkSubtle,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 自绘开关：与深色语言一致，不用系统默认样式。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: DsText.rowTitle),
                  const SizedBox(height: 2),
                  Text(sub, style: DsText.rowSub),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 20,
              decoration: BoxDecoration(
                color: value ? DsColors.primary : DsColors.surface3,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: value ? DsColors.primary : DsColors.hairlineStrong,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? Colors.white : DsColors.inkTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 测试连接结果弹层：逐项列出，失败项给中文解释。
class _ProbeSheet extends StatelessWidget {
  const _ProbeSheet({required this.result});

  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final title = result.allOk
        ? '全部可用'
        : (result.okCount > 0 ? '部分可用' : '全部失败');
    final color = result.allOk
        ? DsColors.success
        : (result.okCount > 0 ? DsColors.warning : DsColors.danger);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: color, size: 7),
              const SizedBox(width: 9),
              Text(title, style: DsText.emptyTitle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.allOk
                ? '余额与用量都能正常读取。'
                : '余额与用量互不影响，按下面提示处理失败项即可。',
            style: const TextStyle(fontSize: 11.5, height: 1.6, color: DsColors.inkSubtle),
          ),
          const SizedBox(height: 16),
          DsPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < result.items.length; i++) ...[
                  if (i > 0) const Hairline(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        StatusDot(
                          color: result.items[i].ok
                              ? DsColors.success
                              : DsColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(result.items[i].label, style: DsText.rowTitle),
                              if (!result.items[i].ok) ...[
                                const SizedBox(height: 2),
                                Text(
                                  result.items[i].hint,
                                  style: DsText.rowSub,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          result.items[i].detail,
                          style: DsText.mono.copyWith(
                            fontSize: 10.5,
                            color: DsColors.inkSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 等待态里的单条步骤。与设计稿的 .step 对应：圆形序号 + 标题 + 说明。
class _LoginStep extends StatelessWidget {
  const _LoginStep({
    required this.index,
    required this.title,
    required this.sub,
    this.last = false,
  });

  final int index;
  final String title;
  final String sub;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: DsColors.primary.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$index',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: DsColors.primaryHover,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DsText.rowTitle),
                  const SizedBox(height: 2),
                  Text(sub, style: DsText.rowSub),
                ],
              ),
            ),
          ],
        ),
      );
}
