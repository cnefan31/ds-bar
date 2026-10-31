/// 服务端（Kotlin）产出的快照 / 配置的 Dart 模型。
///
/// 所有解析都做防御式处理：缺字段、类型不符、JSON 异常都不抛出，退回默认值，
/// 保证界面在任何异常数据下仍可渲染。
library;

class BalanceInfo {
  final String currency;
  final double totalBalance;
  final double grantedBalance;
  final double toppedUpBalance;

  const BalanceInfo({
    this.currency = 'CNY',
    this.totalBalance = 0,
    this.grantedBalance = 0,
    this.toppedUpBalance = 0,
  });

  factory BalanceInfo.fromJson(Map<String, dynamic> json) => BalanceInfo(
        currency: Json.str(json['currency'], 'CNY'),
        totalBalance: Json.numOr(json['totalBalance']),
        grantedBalance: Json.numOr(json['grantedBalance']),
        toppedUpBalance: Json.numOr(json['toppedUpBalance']),
      );
}

class Balance {
  final bool isAvailable;
  final List<BalanceInfo> infos;

  const Balance({this.isAvailable = false, this.infos = const []});

  BalanceInfo? get primary => infos.isEmpty ? null : infos.first;

  static Balance? fromJson(dynamic raw) {
    final json = Json.map(raw);
    if (json == null) return null;
    final list = Json.list(json['infos'])
        .map((e) => BalanceInfo.fromJson(Json.map(e) ?? const {}))
        .toList();
    return Balance(isAvailable: Json.flag(json['isAvailable']), infos: list);
  }
}

/// 一段期间（本月 / 今日）的用量合计。
class UsageBucket {
  final int tokens;
  final int cacheHit;
  final int cacheMiss;
  final int output;
  final int requests;
  final double cost;

  const UsageBucket({
    this.tokens = 0,
    this.cacheHit = 0,
    this.cacheMiss = 0,
    this.output = 0,
    this.requests = 0,
    this.cost = 0,
  });

  factory UsageBucket.fromJson(dynamic raw) {
    final json = Json.map(raw) ?? const {};
    return UsageBucket(
      tokens: Json.intOr(json['tokens']),
      cacheHit: Json.intOr(json['cacheHit']),
      cacheMiss: Json.intOr(json['cacheMiss']),
      output: Json.intOr(json['output']),
      requests: Json.intOr(json['requests']),
      cost: Json.numOr(json['cost']),
    );
  }

  /// 缓存命中率（命中 / 全部输入）。无输入时返回 null。
  double? get cacheHitRate {
    final input = cacheHit + cacheMiss;
    if (input <= 0) return null;
    return cacheHit / input;
  }
}

class ModelUsage {
  final String model;
  final UsageBucket usage;

  const ModelUsage({required this.model, required this.usage});

  factory ModelUsage.fromJson(dynamic raw) {
    final json = Json.map(raw) ?? const {};
    return ModelUsage(
      model: Json.str(json['model'], '(unknown)'),
      usage: UsageBucket.fromJson(json['usage']),
    );
  }
}

class DayUsage {
  final String date;
  final int tokens;
  final int requests;
  final double cost;

  const DayUsage({
    required this.date,
    this.tokens = 0,
    this.requests = 0,
    this.cost = 0,
  });

  factory DayUsage.fromJson(dynamic raw) {
    final json = Json.map(raw) ?? const {};
    return DayUsage(
      date: Json.str(json['date']),
      tokens: Json.intOr(json['tokens']),
      requests: Json.intOr(json['requests']),
      cost: Json.numOr(json['cost']),
    );
  }
}

/// 单个 API Key（平台侧名字）的用量。
class KeyUsage {
  final String name;
  final String? configuredId;
  final bool hasKey;
  final UsageBucket month;
  final UsageBucket today;
  final List<ModelUsage> models;

  const KeyUsage({
    required this.name,
    this.configuredId,
    this.hasKey = false,
    this.month = const UsageBucket(),
    this.today = const UsageBucket(),
    this.models = const [],
  });

  factory KeyUsage.fromJson(dynamic raw) {
    final json = Json.map(raw) ?? const {};
    return KeyUsage(
      name: Json.str(json['name'], 'unknown'),
      configuredId: json['configuredId'] is String
          ? json['configuredId'] as String
          : null,
      hasKey: Json.flag(json['hasKey']),
      month: UsageBucket.fromJson(json['month']),
      today: UsageBucket.fromJson(json['today']),
      models: Json.list(json['models']).map(ModelUsage.fromJson).toList(),
    );
  }
}

class Usage {
  final int year;
  final int month;
  final String currency;
  final UsageBucket monthTotal;
  final UsageBucket? today;
  final List<ModelUsage> models;
  final List<DayUsage> days;
  final List<KeyUsage> perKey;
  final bool perKeyTracked;
  final ApiIssue? todayError;
  final ApiIssue? perKeyError;

  const Usage({
    this.year = 0,
    this.month = 0,
    this.currency = 'CNY',
    this.monthTotal = const UsageBucket(),
    this.today,
    this.models = const [],
    this.days = const [],
    this.perKey = const [],
    this.perKeyTracked = false,
    this.todayError,
    this.perKeyError,
  });

  static Usage? fromJson(dynamic raw) {
    final json = Json.map(raw);
    if (json == null) return null;
    return Usage(
      year: Json.intOr(json['year']),
      month: Json.intOr(json['month']),
      currency: Json.str(json['currency'], 'CNY'),
      monthTotal: UsageBucket.fromJson(json['monthTotal']),
      today: json['today'] == null ? null : UsageBucket.fromJson(json['today']),
      models: Json.list(json['models']).map(ModelUsage.fromJson).toList(),
      days: Json.list(json['days']).map(DayUsage.fromJson).toList(),
      perKey: Json.list(json['perKey']).map(KeyUsage.fromJson).toList(),
      perKeyTracked: Json.flag(json['perKeyTracked']),
      todayError: ApiIssue.fromJson(json['todayError']),
      perKeyError: ApiIssue.fromJson(json['perKeyError']),
    );
  }
}

class ApiIssue {
  final String code;
  final String message;

  const ApiIssue({required this.code, required this.message});

  static ApiIssue? fromJson(dynamic raw) {
    final json = Json.map(raw);
    if (json == null) return null;
    return ApiIssue(
      code: Json.str(json['code'], 'unknown'),
      message: Json.str(json['message']),
    );
  }

  /// 面向用户的简短说明。
  String get hint => switch (code) {
        'missing_credential' => '未配置凭据',
        'auth_failed' => 'API Key 无效',
        'platform_auth' => 'userToken 已过期',
        'platform_rate_limited' => '平台限流',
        'timeout' => '请求超时',
        'invalid_response' => '接口返回异常',
        'fetch_failed' => '网络请求失败',
        'platform_failed' => '平台接口异常',
        _ => '获取失败',
      };
}

/// 单个已配置 key 的余额校验结果。
class KeyCheck {
  final String id;
  final String name;
  final String masked;
  final bool ok;
  final Balance? balance;
  final ApiIssue? error;

  const KeyCheck({
    required this.id,
    required this.name,
    required this.masked,
    this.ok = false,
    this.balance,
    this.error,
  });

  factory KeyCheck.fromJson(dynamic raw) {
    final json = Json.map(raw) ?? const {};
    return KeyCheck(
      id: Json.str(json['id']),
      name: Json.str(json['name'], 'key'),
      masked: Json.str(json['masked']),
      ok: Json.flag(json['ok']),
      balance: Balance.fromJson(json['balance']),
      error: ApiIssue.fromJson(json['error']),
    );
  }
}

class Snapshot {
  final int version;
  final DateTime? fetchedAt;
  final String currency;
  final bool demo;
  final Balance? balance;
  final ApiIssue? balanceError;
  final Usage? usage;
  final ApiIssue? usageError;
  final List<KeyCheck> keyChecks;

  const Snapshot({
    this.version = 1,
    this.fetchedAt,
    this.currency = 'CNY',
    this.demo = false,
    this.balance,
    this.balanceError,
    this.usage,
    this.usageError,
    this.keyChecks = const [],
  });

  static Snapshot? fromJson(dynamic raw) {
    final json = Json.map(raw);
    if (json == null) return null;
    final ts = Json.intOr(json['fetchedAt']);
    return Snapshot(
      version: Json.intOr(json['version'], 1),
      fetchedAt: ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
      currency: Json.str(json['currency'], 'CNY'),
      demo: Json.flag(json['demo']),
      balance: Balance.fromJson(json['balance']),
      balanceError: ApiIssue.fromJson(json['balanceError']),
      usage: Usage.fromJson(json['usage']),
      usageError: ApiIssue.fromJson(json['usageError']),
      keyChecks: Json.list(json['keyChecks']).map(KeyCheck.fromJson).toList(),
    );
  }
}

class AppConfig {
  final List<ConfiguredKey> keys;
  final int refreshMinutes;
  final bool notifyEnabled;
  final bool tileEnabled;
  final bool demoMode;
  final bool userTokenSet;
  final bool cookieSet;
  final DateTime? lastRefreshAt;

  const AppConfig({
    this.keys = const [],
    this.refreshMinutes = 60,
    this.notifyEnabled = true,
    this.tileEnabled = true,
    this.demoMode = false,
    this.userTokenSet = false,
    this.cookieSet = false,
    this.lastRefreshAt,
  });

  factory AppConfig.fromJson(dynamic raw) {
    final json = Json.map(raw) ?? const {};
    final ts = Json.intOr(json['lastRefreshAt']);
    return AppConfig(
      keys: Json.list(json['keys']).map(ConfiguredKey.fromJson).toList(),
      refreshMinutes: Json.intOr(json['refreshMinutes'], 60),
      notifyEnabled: Json.flag(json['notifyEnabled'], true),
      tileEnabled: Json.flag(json['tileEnabled'], true),
      demoMode: Json.flag(json['demoMode']),
      userTokenSet: Json.flag(json['userTokenSet']),
      cookieSet: Json.flag(json['cookieSet']),
      lastRefreshAt: ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
    );
  }

  bool get usageReady => userTokenSet;
}

class ConfiguredKey {
  final String id;
  final String name;

  const ConfiguredKey({required this.id, required this.name});

  factory ConfiguredKey.fromJson(dynamic raw) {
    final json = Json.map(raw) ?? const {};
    return ConfiguredKey(
      id: Json.str(json['id']),
      name: Json.str(json['name'], 'key'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// JSON 取值工具：类型不符时静默兜底。
class Json {
  static Map<String, dynamic>? map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  static List<dynamic> list(dynamic raw) => raw is List ? raw : const [];

  static String str(dynamic raw, [String fallback = '']) =>
      raw is String && raw.isNotEmpty ? raw : fallback;

  static double numOr(dynamic raw, [double fallback = 0]) {
    if (raw is num) {
      final v = raw.toDouble();
      return v.isFinite ? v : fallback;
    }
    if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  static int intOr(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  static bool flag(dynamic raw, [bool fallback = false]) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.toLowerCase();
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return fallback;
  }
}
