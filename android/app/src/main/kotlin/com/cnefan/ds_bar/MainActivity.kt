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
                    if (userToken != null) {
                        prefs.userToken = userToken
                        // 手动填了就标记为手动方式，界面上不再显示「浏览器授权」。
                        if (userToken.isNotBlank()) prefs.loginMethod = DsPrefs.LOGIN_MANUAL
                    }
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
                "testConnection" -> io.execute {
                    val payload = runCatching { ConnectionProbe.run(applicationContext) }.getOrNull()
                    runOnUiThread { result.success(payload) }
                }
                "startBrowserLogin" -> {
                    // 起本地回调服务并在授权准备好后打开系统浏览器。
                    // 状态通过 getLoginState 轮询获取，避免依赖 event channel。
                    val snap = BrowserLogin.start(this) { url ->
                        runCatching {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }.onFailure {
                            BrowserLogin.cancel(applicationContext)
                        }
                    }
                    result.success(BrowserLogin.snapshot(this).let { snapToJson(it) })
                }
                "cancelBrowserLogin" -> {
                    BrowserLogin.cancel(this)
                    result.success(snapToJson(BrowserLogin.snapshot(this)))
                }
                "getLoginState" -> result.success(snapToJson(BrowserLogin.snapshot(this)))
                "signOutPlatform" -> {
                    BrowserLogin.signOut(this)
                    result.success(snapToJson(BrowserLogin.snapshot(this)))
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

        // 启动即恢复定时刷新兜底：系统 force-stop 或用户「清除数据」会清掉已注册
        // 的 job（JobScheduler 与 WorkManager 同此行为），进 App 时补回来。
        if (prefs.tileEnabled || prefs.notifyEnabled) {
            RefreshScheduler.schedule(this, prefs.refreshMinutes)
        }
        BalanceNotification.ensureChannel(this)
        if (prefs.notifyEnabled) {
            BalanceNotification.updateFromCache(this, prefs)
        }
    }

    private fun snapToJson(s: BrowserLogin.Snapshot): String {
        return org.json.JSONObject()
            .put("phase", s.phase)
            .put("authorizeUrl", s.authorizeUrl ?: "")
            .put("expiresAt", s.expiresAt)
            .put("accountHint", s.accountHint ?: "")
            .put("errorCode", s.errorCode ?: "")
            .put("errorMessage", s.errorMessage ?: "")
            .put("loginMethod", s.loginMethod)
            .toString()
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
