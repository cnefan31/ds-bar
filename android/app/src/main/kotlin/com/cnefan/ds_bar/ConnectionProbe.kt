package com.cnefan.ds_bar

import android.content.Context
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject

/**
 * 「测试连接」：逐项校验每个凭据，返回结构化结果供 UI 逐条渲染。
 *
 * 设计要点：
 *  - 每一项独立成败，不因一项失败中断（用户要看清是哪一环坏了）
 *  - 只做只读 GET，不产生消耗
 *  - 返回稳定错误码，界面据此给中文说明
 */
object ConnectionProbe {

    /** 单项结果。 */
    private class Item(
        val target: String,
        val label: String,
        val ok: Boolean,
        val detail: String,
        val code: String = ""
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("target", target)
            .put("label", label)
            .put("ok", ok)
            .put("detail", detail)
            .put("code", code)
    }

    fun run(context: Context): String {
        val prefs = DsPrefs(context)
        val items = JSONArray()

        // 1. 逐个 API Key：调官方余额接口，200 即有效。
        val keys = prefs.keys()
        if (keys.isEmpty()) {
            items.put(
                Item("apiKey", "API Key", false, "尚未添加", DsHttp.ERR_MISSING_CREDENTIAL).toJson()
            )
        } else {
            for (key in keys) {
                items.put(probeApiKey(key))
            }
        }

        // 2. 平台 userToken：调 usage/amount，看是否 401。
        val token = prefs.userToken
        if (token.isBlank()) {
            items.put(
                Item("platform", "平台 userToken", false, "未配置", DsHttp.ERR_MISSING_CREDENTIAL).toJson()
            )
        } else {
            items.put(probePlatform(prefs))
        }

        val payload = JSONObject()
            .put("items", items)
            .put("testedAt", System.currentTimeMillis())

        val allOk = (0 until items.length()).all { items.getJSONObject(it).getBoolean("ok") }
        payload.put("allOk", allOk)
        return payload.toString()
    }

    private fun probeApiKey(key: ApiKeyEntry): JSONObject {
        return try {
            val res = DsHttp.get(
                DsRepository.BALANCE_URL,
                mapOf("Authorization" to "Bearer ${key.key}")
            )
            when (res.status) {
                200 -> {
                    val json = runCatching { JSONObject(res.text) }.getOrNull()
                    val info = json?.optJSONArray("balance_infos")?.optJSONObject(0)
                    val sym = Fmt.currencySymbol(info?.optString("currency"))
                    val amount = info?.optDouble("total_balance", Double.NaN) ?: Double.NaN
                    val detail = if (amount.isNaN()) "200 有效"
                    else "200 · $sym" + Fmt.money(amount)
                    Item("apiKey", "API Key · ${key.name}", true, detail).toJson()
                }
                401, 403 -> Item(
                    "apiKey", "API Key · ${key.name}", false,
                    "${res.status} 未授权", DsHttp.ERR_AUTH_FAILED
                ).toJson()
                else -> Item(
                    "apiKey", "API Key · ${key.name}", false,
                    "HTTP ${res.status}", DsHttp.ERR_FETCH_FAILED
                ).toJson()
            }
        } catch (e: DsException) {
            Item("apiKey", "API Key · ${key.name}", false, e.message ?: "请求失败", e.code).toJson()
        } catch (t: Throwable) {
            Item("apiKey", "API Key · ${key.name}", false, t.message ?: "请求失败", DsHttp.ERR_FETCH_FAILED).toJson()
        }
    }

    private fun probePlatform(prefs: DsPrefs): JSONObject {
        val now = java.util.Calendar.getInstance()
        val url = DsRepository.USAGE_AMOUNT_URL +
            "?month=" + (now.get(java.util.Calendar.MONTH) + 1) +
            "&year=" + now.get(java.util.Calendar.YEAR)

        val headers = mutableMapOf(
            "Authorization" to "Bearer ${prefs.userToken}",
            "User-Agent" to DsRepository.UA,
            "Referer" to "https://platform.deepseek.com/usage",
            "x-client-locale" to "zh_CN",
            "x-client-platform" to "web",
            "x-client-version" to "1.0.0"
        )
        if (prefs.cookie.isNotBlank()) headers["Cookie"] = prefs.cookie

        return try {
            val res = DsHttp.get(url, headers)
            when (res.status) {
                200 -> {
                    val ok = res.text.trimStart().startsWith("{")
                    if (ok) Item("platform", "平台 userToken", true, "200 有效").toJson()
                    else Item(
                        "platform", "平台 userToken", false,
                        "返回非 JSON，可能需补 Cookie", DsHttp.ERR_PLATFORM_FAILED
                    ).toJson()
                }
                401, 403 -> Item(
                    "platform", "平台 userToken", false,
                    "${res.status} 未授权，已过期", DsHttp.ERR_PLATFORM_AUTH
                ).toJson()
                429 -> Item(
                    "platform", "平台 userToken", false,
                    "429 限流，稍后重试", DsHttp.ERR_PLATFORM_RATE_LIMITED
                ).toJson()
                else -> Item(
                    "platform", "平台 userToken", false,
                    "HTTP ${res.status}", DsHttp.ERR_PLATFORM_FAILED
                ).toJson()
            }
        } catch (e: DsException) {
            Item("platform", "平台 userToken", false, e.message ?: "请求失败", e.code).toJson()
        } catch (t: Throwable) {
            Item("platform", "平台 userToken", false, t.message ?: "请求失败", DsHttp.ERR_FETCH_FAILED).toJson()
        }
    }
}
