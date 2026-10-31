import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

/// 与 Kotlin 侧 MethodChannel 的桥接。
///
/// 数据获取、缓存、通知、磁贴全部在原生层完成；Dart 只做展示与配置写入。
/// 凭据明文只在原生层持有，Dart 侧不缓存，避免泄露面扩大。
class NativeBridge {
  static const channel = MethodChannel('com.cnefan.ds_bar/native');

  /// 上次调用的错误码，便于界面区分「通道不可用」与其他问题。
  String? lastErrorCode;

  Future<AppConfig> getConfig() async {
    final raw = await _invoke<String>('getConfig');
    return AppConfig.fromJson(jsonDecode(raw ?? '{}'));
  }

  Future<Snapshot?> getSnapshot() async {
    final raw = await _invoke<String>('getSnapshot');
    if (raw == null || raw.isEmpty) return null;
    return Snapshot.fromJson(jsonDecode(raw));
  }

  Future<Snapshot?> refresh() async {
    final raw = await _invoke<String>('refresh');
    if (raw == null || raw.isEmpty) return null;
    return Snapshot.fromJson(jsonDecode(raw));
  }

  /// 追加一个 key。密钥只在这一次调用中从 Dart 传入，不保留。
  Future<AppConfig> appendKey({required String name, required String key}) async {
    final raw = await _invoke<String>('appendKey', {'name': name, 'key': key});
    return AppConfig.fromJson(jsonDecode(raw ?? '{}'));
  }

  Future<AppConfig> removeKey(String id) async {
    final raw = await _invoke<String>('removeKey', {'id': id});
    return AppConfig.fromJson(jsonDecode(raw ?? '{}'));
  }

  Future<AppConfig> saveSettings({
    int? refreshMinutes,
    bool? notifyEnabled,
    bool? tileEnabled,
    bool? demoMode,
    String? userToken,
    String? cookie,
  }) async {
    final raw = await _invoke<String>('saveSettings', {
      'refreshMinutes': ?refreshMinutes,
      'notifyEnabled': ?notifyEnabled,
      'tileEnabled': ?tileEnabled,
      'demoMode': ?demoMode,
      'userToken': ?userToken,
      'cookie': ?cookie,
    });
    return AppConfig.fromJson(jsonDecode(raw ?? '{}'));
  }

  Future<void> requestNotificationPermission() async {
    await _invoke<void>('requestNotificationPermission');
  }

  Future<void> openUrl(String url) async {
    await _invoke<void>('openUrl', {'url': url});
  }

  Future<bool> openQsTileSettings() async {
    final ok = await _invoke<bool>('openQsTileSettings');
    return ok ?? false;
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      lastErrorCode = null;
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      lastErrorCode = e.code;
      return null;
    } on MissingPluginException {
      lastErrorCode = 'missing_plugin';
      return null;
    }
  }
}
