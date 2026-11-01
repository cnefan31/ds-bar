package com.cnefan.ds_bar

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class ApiKeyEntry(val id: String, val name: String, val key: String) {
    val masked: String
        get() = when {
            key.length <= 8 -> maskTail(key)
            else -> key.substring(0, 5) + "…" + key.takeLast(4)
        }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        // 打码后的 key 尾号，供设置页核对是哪一把；不泄露明文。
        .put("masked", masked)

    companion object {
        private fun maskTail(key: String) = if (key.length <= 4) "…" else "…" + key.takeLast(4)
    }
}

/**
 * 本地配置与缓存。凭据存于应用私有 SharedPreferences，仅本 App 可读。
 */
class DsPrefs(context: Context) {

    private val sp = context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    var userToken: String
        get() = sp.getString(KEY_USER_TOKEN, "") ?: ""
        set(value) = sp.edit().putString(KEY_USER_TOKEN, value.trim()).apply()

    var cookie: String
        get() = sp.getString(KEY_COOKIE, "") ?: ""
        set(value) = sp.edit().putString(KEY_COOKIE, value.trim()).apply()

    var refreshMinutes: Int
        get() = sp.getInt(KEY_REFRESH_MINUTES, DEFAULT_REFRESH_MINUTES)
        set(value) = sp.edit().putInt(KEY_REFRESH_MINUTES, value.coerceIn(15, 1440)).apply()

    var notifyEnabled: Boolean
        get() = sp.getBoolean(KEY_NOTIFY, true)
        set(value) = sp.edit().putBoolean(KEY_NOTIFY, value).apply()

    var tileEnabled: Boolean
        get() = sp.getBoolean(KEY_TILE, true)
        set(value) = sp.edit().putBoolean(KEY_TILE, value).apply()

    var demoMode: Boolean
        get() = sp.getBoolean(KEY_DEMO, false)
        set(value) = sp.edit().putBoolean(KEY_DEMO, value).apply()

    var lastRefreshAt: Long
        get() = sp.getLong(KEY_LAST_REFRESH, 0L)
        set(value) = sp.edit().putLong(KEY_LAST_REFRESH, value).apply()

    /** 登录方式：manual（粘贴 userToken）或 browser（一键授权）。仅用于界面展示。 */
    var loginMethod: String
        get() = sp.getString(KEY_LOGIN_METHOD, LOGIN_MANUAL) ?: LOGIN_MANUAL
        set(value) = sp.edit().putString(KEY_LOGIN_METHOD, value).apply()

    /** 打码后的账号标识（如 1•••••@qq.com）；拿不到就是空串，界面不显示占位。 */
    var accountHint: String
        get() = sp.getString(KEY_ACCOUNT_HINT, "") ?: ""
        set(value) = sp.edit().putString(KEY_ACCOUNT_HINT, value).apply()

    /** 设备标识，只用于 auth_exchange，稳定即可，不含个人信息。 */
    var loginDeviceId: String
        get() {
            val v = sp.getString(KEY_DEVICE_ID, null)
            if (!v.isNullOrBlank()) return v
            val fresh = java.util.UUID.randomUUID().toString()
            sp.edit().putString(KEY_DEVICE_ID, fresh).apply()
            return fresh
        }
        set(value) = sp.edit().putString(KEY_DEVICE_ID, value).apply()

    var cachedSnapshot: String?
        get() = sp.getString(KEY_SNAPSHOT, null)
        set(value) = sp.edit().putString(KEY_SNAPSHOT, value).apply()

    fun keys(): List<ApiKeyEntry> {
        val raw = sp.getString(KEY_KEYS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val key = o.optString("key")
                if (key.isBlank()) return@mapNotNull null
                ApiKeyEntry(
                    id = o.optString("id").ifBlank { UUID.randomUUID().toString() },
                    name = o.optString("name").ifBlank { "key" },
                    key = key
                )
            }
        } catch (t: Throwable) {
            emptyList()
        }
    }

    fun saveKeys(entries: List<ApiKeyEntry>) {
        val arr = JSONArray()
        entries.forEach { e ->
            arr.put(
                JSONObject()
                    .put("id", e.id)
                    .put("name", e.name)
                    .put("key", e.key)
            )
        }
        sp.edit().putString(KEY_KEYS, arr.toString()).apply()
    }

    fun addKey(name: String, key: String): ApiKeyEntry {
        val entries = keys().toMutableList()
        val entry = ApiKeyEntry(UUID.randomUUID().toString(), name.ifBlank { "key ${entries.size + 1}" }, key.trim())
        entries.add(entry)
        saveKeys(entries)
        return entry
    }

    fun removeKey(id: String) {
        saveKeys(keys().filterNot { it.id == id })
    }

    fun renameKey(id: String, name: String) {
        saveKeys(keys().map { if (it.id == id) it.copy(name = name.ifBlank { it.name }) else it })
    }

    fun configJson(): JSONObject {
        val arr = JSONArray()
        keys().forEach { arr.put(it.toJson()) }
        return JSONObject()
            .put("keys", arr)
            .put("refreshMinutes", refreshMinutes)
            .put("notifyEnabled", notifyEnabled)
            .put("tileEnabled", tileEnabled)
            .put("demoMode", demoMode)
            .put("userTokenSet", userToken.isNotBlank())
            .put("loginMethod", loginMethod)
            .put("accountHint", accountHint)
            .put("cookieSet", cookie.isNotBlank())
            .put("lastRefreshAt", lastRefreshAt)
    }

    companion object {
        const val NAME = "ds_bar"
        const val DEFAULT_REFRESH_MINUTES = 60
        const val LOGIN_MANUAL = "manual"
        const val LOGIN_BROWSER = "browser"
        private const val KEY_LOGIN_METHOD = "login_method"
        private const val KEY_ACCOUNT_HINT = "account_hint"
        private const val KEY_DEVICE_ID = "login_device_id"
        private const val KEY_KEYS = "api_keys"
        private const val KEY_USER_TOKEN = "user_token"
        private const val KEY_COOKIE = "cookie"
        private const val KEY_REFRESH_MINUTES = "refresh_minutes"
        private const val KEY_NOTIFY = "notify_enabled"
        private const val KEY_TILE = "tile_enabled"
        private const val KEY_DEMO = "demo_mode"
        private const val KEY_LAST_REFRESH = "last_refresh_at"
        private const val KEY_SNAPSHOT = "cached_snapshot"
    }
}
