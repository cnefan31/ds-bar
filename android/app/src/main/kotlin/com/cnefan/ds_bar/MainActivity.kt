package com.cnefan.ds_bar

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val prefs = DsPrefs(this)
        android.util.Log.i("DsBarNotify", "engine configured; notifyEnabled=" + prefs.notifyEnabled +
            " tileEnabled=" + prefs.tileEnabled + " refresh=" + prefs.refreshMinutes)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getConfig" -> result.success(prefs.configJson().toString())
                "getSnapshot" -> result.success(DsRepository(this).snapshotJson()?.toString())
                "refresh" -> io.execute {
                    val snapshot = try {
                        DsRefresh.perform(applicationContext)?.toString()
                    } catch (t: Throwable) {
                        null
                    }
                    runOnUiThread { result.success(snapshot) }
                }
                "appendKey" -> {
                    val name = call.argument<String>("name").orEmpty().trim()
                    val key = call.argument<String>("key").orEmpty().trim()
                    if (key.isBlank()) {
                        result.error("bad_key", "API Key 不能为空", null)
                    } else {
                        prefs.addKey(name, key)
                        result.success(prefs.configJson().toString())
                    }
                }
                "removeKey" -> {
                    val id = call.argument<String>("id").orEmpty()
                    if (id.isNotBlank()) prefs.removeKey(id)
                    result.success(prefs.configJson().toString())
                }
                "saveSettings" -> {
                    val refresh = call.argument<Int>("refreshMinutes")
                    val notify = call.argument<Boolean>("notifyEnabled")
                    val tile = call.argument<Boolean>("tileEnabled")
                    val demo = call.argument<Boolean>("demoMode")
                    val userToken = call.argument<String>("userToken")
                    val cookie = call.argument<String>("cookie")
                    if (refresh != null) prefs.refreshMinutes = refresh
                    if (notify != null) prefs.notifyEnabled = notify
                    if (tile != null) prefs.tileEnabled = tile
                    if (demo != null) prefs.demoMode = demo
                    if (userToken != null) prefs.userToken = userToken
                    if (cookie != null) prefs.cookie = cookie

                    if (prefs.notifyEnabled) {
                        BalanceNotification.updateFromCache(this, prefs)
                    } else {
                        BalanceNotification.cancel(this)
                    }
                    // 定时刷新服务于通知与磁贴两者，任一开启就要跑。
                    // 早期实现只看 tileEnabled，导致「只开通知、关磁贴」时后台不再刷新。
                    if (prefs.tileEnabled || prefs.notifyEnabled) {
                        RefreshScheduler.schedule(this, prefs.refreshMinutes)
                    } else {
                        RefreshScheduler.cancel(this)
                    }
                    if (prefs.tileEnabled) {
                        BalanceTileService.requestUpdate(this)
                    }
                    result.success(prefs.configJson().toString())
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 77)
                    }
                    result.success(null)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("bad_url", "url 为空", null)
                    } else {
                        runCatching {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(null)
                        }.onFailure { result.error("open_failed", it.message, null) }
                    }
                }
                "openQsTileSettings" -> {
                    val ok = runCatching {
                        startActivity(Intent("android.service.quicksettings.action.QS_TILE_SETTINGS"))
                        true
                    }.getOrDefault(false)
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }

        // 启动即恢复定时刷新（多进程被杀后 WorkManager 仍保留，这里兜底）
        if (prefs.tileEnabled || prefs.notifyEnabled) {
            RefreshScheduler.schedule(this, prefs.refreshMinutes)
        }
        BalanceNotification.ensureChannel(this)
        if (prefs.notifyEnabled) {
            BalanceNotification.updateFromCache(this, prefs)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 77) {
            val prefs = DsPrefs(this)
            if (prefs.notifyEnabled) BalanceNotification.updateFromCache(this, prefs)
        }
    }

    companion object {
        const val CHANNEL = "com.cnefan.ds_bar/native"
    }
}
