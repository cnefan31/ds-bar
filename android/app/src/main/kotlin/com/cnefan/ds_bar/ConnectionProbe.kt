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
            items.put(probePlatform(prefs, context))
        }

        // 3. 浏览器登录拿到的 token 类型未知：分别用两种鉴权头试同一接口，
        //    以及平台可能存在的 key 列表接口，用来判定这个 token 能做什么。
        if (token.isNotBlank()) {
            probeTokenCapabilities(prefs).forEach { items.put(it) }
        }

        val payload = JSONObject()
            .put("items", items)
            .put("testedAt", System.currentTimeMillis())

        val allOk = (0 until items.length()).all { items.getJSONObject(it).getBoolean("ok") }
        payload.put("allOk", allOk)
        return payload.toString()
    }

    /** 只做只读 GET，逐一试探 token 的可用范围；结果只有状态码，不含凭据。 */
    private fun probeTokenCapabilities(prefs: DsPrefs): List<JSONObject> {
        val now = java.util.Calendar.getInstance()
        val usageUrl = DsRepository.USAGE_AMOUNT_URL +
            "?month=" + (now.get(java.util.Calendar.MONTH) + 1) +
            "&year=" + now.get(java.util.Calendar.YEAR)
        val token = prefs.userToken
        val base = mapOf(
            "User-Agent" to DsRepository.UA,
            "Referer" to "https://platform.deepseek.com/usage",
            "x-client-locale" to "zh_CN",
            "x-client-platform" to "web",
            "x-client-version" to "1.0.0"
        )
        val out = mutableListOf<JSONObject>()

        fun probe(target: String, label: String, url: String, extra: Map<String, String>) {
            val headers = base + extra
            out.add(
                try {
                    val res = DsHttp.get(url, headers)
                    // 必须校验业务码：平台会用 HTTP 200 + {"code":40003} 表示鉴权失败，
                    // 只看状态码会把它当成功（之前就因此误判过）。
                    val json = runCatching { JSONObject(res.text) }.getOrNull()
                    val bizCode = json?.optInt("code", -1)
                    val ok = res.status == 200 && bizCode == 0
                    val detail = when {
                        res.status != 200 -> "HTTP ${res.status}"
                        json == null -> "200 非JSON"
                        else -> "200 code=$bizCode"
                    }
                    Item(
                        target, label, ok, detail,
                        if (ok) "" else "probe_${res.status}_$bizCode"
                    ).toJson()
                } catch (e: DsException) {
                    Item(target, label, false, e.message ?: "请求失败", e.code).toJson()
                } catch (t: Throwable) {
                    Item(target, label, false, t.message ?: "请求失败", DsHttp.ERR_FETCH_FAILED).toJson()
                }
            )
        }

        probe("bearerUsage", "用量 · Bearer 头", usageUrl, mapOf("Authorization" to "Bearer $token"))
        probe("dshUsage", "用量 · x-dsh-auth-token", usageUrl, mapOf("x-dsh-auth-token" to token))
        probe(
            "dshSummary", "账户摘要 · x-dsh-auth-token",
            "https://platform.deepseek.com/api/v0/users/get_user_summary",
            mapOf("x-dsh-auth-token" to token)
        )
        probe(
            "dshProfile", "账户资料 · x-dsh-auth-token",
            "https://platform.deepseek.com/auth-api/v0/users/current",
            mapOf("x-dsh-auth-token" to token)
        )
        probe(
            "keysList", "Key 列表 · x-dsh-auth-token",
            "https://platform.deepseek.com/api/v0/users/get_api_keys",
            mapOf("x-dsh-auth-token" to token)
        )
        probe(
            "keysListBearer", "Key 列表 · Bearer 头",
            "https://platform.deepseek.com/api/v0/users/get_api_keys",
            mapOf("Authorization" to "Bearer $token")
        )
        return out
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

    private fun probePlatform(prefs: DsPrefs, context: Context): JSONObject {
        val now = java.util.Calendar.getInstance()
        val url = DsRepository.USAGE_AMOUNT_URL +
            "?month=" + (now.get(java.util.Calendar.MONTH) + 1) +
            "&year=" + now.get(java.util.Calendar.YEAR)

        // 鉴权头随登录方式而变，直接复用仓库的实现，避免两处判断不一致。
        val headers = DsRepository(context).platformHeaders()

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
