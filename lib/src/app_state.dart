import 'package:flutter/foundation.dart';

import 'models.dart';
import 'native_bridge.dart';

/// 全应用状态：配置 + 最近快照 + 刷新状态。
class AppState extends ChangeNotifier {
  AppState({NativeBridge? bridge}) : _bridge = bridge ?? NativeBridge();

  final NativeBridge _bridge;

  AppConfig _config = const AppConfig();
  Snapshot? _snapshot;
  bool _loading = false;
  bool _refreshing = false;
  String? _lastError;
  DateTime? _lastRefreshAt;

  AppConfig get config => _config;
  Snapshot? get snapshot => _snapshot;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  String? get lastError => _lastError;
  DateTime? get lastRefreshAt => _lastRefreshAt ?? _config.lastRefreshAt;

  /// 通道不可用（例如在桌面端跑测试）时为 true。
  bool get bridgeUnavailable => _bridge.lastErrorCode == 'missing_plugin';

  /// 首次加载：读配置 + 读缓存快照。不做网络请求。
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final config = await _bridge.getConfig();
    _config = config;
    final cached = await _bridge.getSnapshot();
    if (cached != null) _snapshot = cached;
    _loading = false;
    notifyListeners();

    // 应用启动时若配置了凭据且缓存过旧，静默拉一次
    final last = _snapshot?.fetchedAt;
    final stale = last == null ||
        DateTime.now().difference(last).inMinutes >= _config.refreshMinutes;
    if (stale && (_config.keys.isNotEmpty || _config.demoMode)) {
      // 不阻塞首屏渲染
      unawaited(refresh(silent: true));
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent) _lastError = null;
    notifyListeners();
    try {
      final result = await _bridge.refresh();
      if (result != null) {
        _snapshot = result;
        _lastError = null;
        _lastRefreshAt = result.fetchedAt;
      } else {
        _lastError = '同步失败，请检查网络或凭据';
      }
      _config = await _bridge.getConfig();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// 原生侧已把配置变更落盘，这里只替换内存副本。
  void replaceConfig(AppConfig config) {
    _config = config;
    notifyListeners();
  }

  Future<void> updateSettings({
    int? refreshMinutes,
    bool? notifyEnabled,
    bool? tileEnabled,
    bool? demoMode,
    String? userToken,
    String? cookie,
  }) async {
    _config = await _bridge.saveSettings(
      refreshMinutes: refreshMinutes,
      notifyEnabled: notifyEnabled,
      tileEnabled: tileEnabled,
      demoMode: demoMode,
      userToken: userToken,
      cookie: cookie,
    );
    notifyListeners();
  }

  /// 用量按 key 汇总的总和，用于校验「各 key 之和 ≈ 账户总量」。
  double get perKeyCostSum =>
      (_snapshot?.usage?.perKey ?? const []).fold(0.0, (s, e) => s + e.month.cost);
}

void unawaited(Future<void> future) {
  future.catchError((_) {});
}
