package com.cnefan.ds_bar

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.zip.ZipInputStream

/**
 * 取数入口：官方余额接口 + 平台用量接口，汇总成一个快照 JSON 供 UI / 通知 / 磁贴共用。
 */
class DsRepository(private val context: Context) {

    private val prefs = DsPrefs(context)

    private val platformBase = "https://platform.deepseek.com"
    private val summaryUrl = "$platformBase/api/v0/users/get_user_summary"
    private val apiKeysUrl = "$platformBase/api/v0/users/get_api_keys"

    fun snapshotJson(): JSONObject? = prefs.cachedSnapshot?.let {
        runCatching { JSONObject(it) }.getOrNull()
    }

    fun configJson(): JSONObject = prefs.configJson()

    /** 刷新并落盘；返回快照 JSON。 */
    fun refresh(): JSONObject {
        val snapshot = try {
            if (prefs.demoMode) DemoData.snapshot() else fetchSnapshot()
        } catch (t: Throwable) {
            android.util.Log.e("DsBarRefresh", "snapshot build failed", t)
            throw t
        }
        prefs.cachedSnapshot = snapshot.toString()
        prefs.lastRefreshAt = System.currentTimeMillis()
        return snapshot
    }

    private fun fetchSnapshot(): JSONObject {
        val keys = prefs.keys()
        val root = JSONObject()
            .put("version", SNAPSHOT_VERSION)
            .put("fetchedAt", System.currentTimeMillis())
            .put("currency", "CNY")
            .put("demo", false)

        // ---- 余额（账户级）与各 key 校验 ----
        val balances = JSONArray()
        var keyError: JSONObject? = null
        var accountBalance: JSONObject? = null
        for (entry in keys) {
            try {
                val balance = fetchBalance(entry.key)
                if (accountBalance == null) accountBalance = balance
                balances.put(
                    JSONObject()
                        .put("id", entry.id)
                        .put("name", entry.name)
                        .put("masked", entry.masked)
                        .put("ok", true)
                        .put("balance", balance)
                )
            } catch (e: DsException) {
                if (keyError == null) keyError = JSONObject().put("code", e.code).put("message", e.message ?: "")
                balances.put(
                    JSONObject()
                        .put("id", entry.id)
                        .put("name", entry.name)
                        .put("masked", entry.masked)
                        .put("ok", false)
                        .put("error", JSONObject().put("code", e.code).put("message", e.message ?: ""))
                )
            }
        }
        root.put("keyChecks", balances)
        if (accountBalance != null) {
            root.put("balance", accountBalance)
        } else if (keys.isEmpty()) {
            root.put("balanceError", JSONObject().put("code", DsHttp.ERR_MISSING_CREDENTIAL).put("message", "未添加 API Key"))
        } else {
            root.put("balanceError", keyError ?: JSONObject().put("code", DsHttp.ERR_AUTH_FAILED).put("message", "余额获取失败"))
        }

        // ---- 浏览器登录后：用平台账户摘要补余额（不需要 API Key） ----
        // 官方 /user/balance 需要 sk- 密钥；平台摘要只要登录态，两条路互不阻塞。
        if (prefs.userToken.isNotBlank()) {
            if (!root.has("balance") || root.optJSONObject("balance") == null) {
                try {
                    root.put("balance", fetchPlatformSummary())
                    root.remove("balanceError")
                    root.put("balanceSource", "platform")
                } catch (e: DsException) {
                    // 平台摘要失败不覆盖官方接口的结论
                    if (!root.has("balanceError")) {
                        root.put("balanceError", JSONObject().put("code", e.code).put("message", e.message ?: ""))
                    }
                }
            } else {
                root.put("balanceSource", "official")
            }

            // ---- 平台 Key 列表：登录后自动发现，不需要逐个手输 ----
            try {
                root.put("platformKeys", fetchPlatformKeys())
            } catch (e: DsException) {
                root.put("platformKeysError", JSONObject().put("code", e.code).put("message", e.message ?: ""))
            }
        }

        // ---- 用量（平台会话） ----
        val token = prefs.userToken
        if (token.isBlank()) {
            root.put("usageError", JSONObject().put("code", DsHttp.ERR_MISSING_CREDENTIAL).put("message", "未配置平台 userToken"))
        } else {
            try {
                root.put("usage", fetchUsage(keys))
            } catch (e: DsException) {
                root.put("usageError", JSONObject().put("code", e.code).put("message", e.message ?: ""))
            }
        }
        return root
    }

    // ---------- 平台账户摘要（登录态即可，无需 API Key） ----------

    /**
     * GET /api/v0/users/get_user_summary → 归一成与官方余额相同的结构。
     *
     * 字段（实测）：normal_wallets[]{currency,balance} 为充值余额，
     * bonus_wallets[]{currency,balance} 为赠送余额，total_costs[]{currency,amount} 为累计消费。
     * 归一后 UI / 通知 / 磁贴无需区分来源。
     */
    private fun fetchPlatformSummary(): JSONObject {
        val res = platformGet(summaryUrl)
        val biz = unwrapBiz(res, "账户摘要")
        val normal = biz.optJSONArray("normal_wallets")
        val bonus = biz.optJSONArray("bonus_wallets")
        val currency = (normal?.optJSONObject(0) ?: bonus?.optJSONObject(0))
            ?.optString("currency")
            ?.ifBlank { "CNY" } ?: "CNY"
        val topped = normal?.optJSONObject(0)?.optDouble("balance", 0.0) ?: 0.0
        val granted = bonus?.optJSONObject(0)?.optDouble("balance", 0.0) ?: 0.0
        val total = topped + granted

        val cost = biz.optJSONArray("total_costs")?.optJSONObject(0)?.optDouble("amount", 0.0) ?: 0.0
        val infos = JSONArray().put(
            JSONObject()
                .put("currency", currency)
                .put("totalBalance", total)
                .put("grantedBalance", granted)
                .put("toppedUpBalance", topped)
        )
        return JSONObject()
            .put("isAvailable", total > 0.0)
            .put("infos", infos)
            .put("totalCost", cost)
    }

    // ---------- 平台 API Key 列表 ----------

    /**
     * GET /api/v0/users/get_api_keys → 账号下全部 key。
     *
     * 注意：平台**不返回 key 明文**（只有 sensitive_id 打码值与 tracking_id），
     * 所以这些 key 不能拿去调官方余额接口，只能用于展示与对照用量。
     */
    private fun fetchPlatformKeys(): JSONArray {
        val res = platformGet(apiKeysUrl)
        val biz = unwrapBiz(res, "Key 列表")
        val arr = biz.optJSONArray("api_keys") ?: JSONArray()
        val out = JSONArray()
        val quota = biz.optJSONObject("key_quota")?.optJSONObject("total")
        for (i in 0 until arr.length()) {
            val k = arr.optJSONObject(i) ?: continue
            out.put(
                JSONObject()
                    .put("name", k.optString("name"))
                    .put("masked", k.optString("sensitive_id"))
                    .put("trackingId", k.optString("tracking_id"))
                    .put("keyType", k.optString("key_type"))
                    .put("createdAt", epochToMillis(k.optLong("created_at", 0L)))
                    .put("lastUse", epochToMillis(k.optLong("last_use", 0L)))
                    .put("quotaUsed", quota?.optDouble("used", 0.0) ?: 0.0)
                    .put("quotaLimit", quota?.optDouble("limit", 0.0) ?: 0.0)
            )
        }
        return out
    }

    /**
     * 平台的时间戳是**秒**（实测 created_at=1790734297、last_use=1793473391），
     * 直接当毫秒用会变成 1970-01-22，界面显示的时间就全错了。
     * 这里统一归一到毫秒；1e11 毫秒约等于 1973 年，比它小的只可能是秒。
     */
    internal fun epochToMillis(value: Long): Long = when {
        value <= 0L -> 0L
        value < 100_000_000_000L -> value * 1000L
        else -> value
    }

    /** 平台统一信封：{code,msg,data{biz_code,biz_msg,biz_data}}。 */
    private fun unwrapBiz(res: DsHttp.Response, what: String): JSONObject {
        val json = runCatching { JSONObject(res.text) }.getOrElse {
            throw DsException(DsHttp.ERR_PLATFORM_FAILED, "${what}返回非 JSON")
        }
        val code = json.optInt("code", -1)
        if (code != 0) throw DsException(DsHttp.ERR_PLATFORM_FAILED, "${what}失败：${json.optString("msg").ifBlank { "code=$code" }}")
        val data = json.optJSONObject("data") ?: throw DsException(DsHttp.ERR_PLATFORM_FAILED, "${what}缺少 data")
        val bizCode = data.optInt("biz_code", -1)
        if (bizCode != 0) throw DsException(DsHttp.ERR_PLATFORM_FAILED, "${what}失败：${data.optString("biz_msg").ifBlank { "biz_code=$bizCode" }}")
        return data.optJSONObject("biz_data") ?: throw DsException(DsHttp.ERR_PLATFORM_FAILED, "${what}缺少 biz_data")
    }

    // ---------- 官方余额 ----------

    private fun fetchBalance(apiKey: String): JSONObject {
        if (apiKey.isBlank()) throw DsException(DsHttp.ERR_MISSING_CREDENTIAL, "API Key 为空")
        val res = DsHttp.get(BALANCE_URL, mapOf("Authorization" to "Bearer $apiKey"))
        if (res.status == 401 || res.status == 403) throw DsException(DsHttp.ERR_AUTH_FAILED, "API Key 无效", res.status)
        if (res.status != 200) throw DsException(DsHttp.ERR_FETCH_FAILED, "余额接口 HTTP ${res.status}", res.status)
        val json = runCatching { JSONObject(res.text) }.getOrElse {
            throw DsException(DsHttp.ERR_INVALID_RESPONSE, "余额接口返回无法解析")
        }
        val infos = json.optJSONArray("balance_infos") ?: throw DsException(DsHttp.ERR_INVALID_RESPONSE, "余额接口缺少 balance_infos")
        val out = JSONArray()
        for (i in 0 until infos.length()) {
            val item = infos.optJSONObject(i) ?: continue
            out.put(
                JSONObject()
                    .put("currency", item.optString("currency", "CNY"))
                    .put("totalBalance", UsageParser.parseDoubleOrZero(item.opt("total_balance")))
                    .put("grantedBalance", UsageParser.parseDoubleOrZero(item.opt("granted_balance")))
                    .put("toppedUpBalance", UsageParser.parseDoubleOrZero(item.opt("topped_up_balance")))
            )
        }
        return JSONObject()
            .put("isAvailable", json.optBoolean("is_available", false))
            .put("infos", out)
    }

    // ---------- 平台用量 ----------

    /**
     * 平台请求头。
     *
     * 两种登录态用两种鉴权头，混用会得到 HTTP 200 + code=40003
     * （"Authorization Failed (invalid token)"），看起来像成功、实际全空：
     *  - 手动粘贴的网页 userToken → Authorization: Bearer
     *  - 浏览器授权拿到的账号 grant → x-dsh-auth-token（平台内部接口的约定）
     */
    internal fun platformHeaders(): Map<String, String> {
        val headers = mutableMapOf(
            "User-Agent" to UA,
            "Referer" to "https://platform.deepseek.com/usage",
            "x-client-locale" to "zh_CN",
            "x-client-platform" to "web",
            "x-client-version" to "1.0.0",
            "x-client-timezone-offset" to "28800"
        )
        if (prefs.loginMethod == DsPrefs.LOGIN_BROWSER) {
            headers["x-dsh-auth-token"] = prefs.userToken
        } else {
            headers["Authorization"] = "Bearer ${prefs.userToken}"
        }
        if (prefs.cookie.isNotBlank()) headers["Cookie"] = prefs.cookie
        return headers
    }

    private fun platformGet(url: String): DsHttp.Response {
        val res = DsHttp.get(url, platformHeaders())
        android.util.Log.i(
            "DsBarRefresh",
            "platform GET ${url.substringAfter("deepseek.com")} -> ${res.status} cookie=${prefs.cookie.isNotBlank()} len=${res.body.size}"
        )
        when (res.status) {
            401, 403 -> throw DsException(DsHttp.ERR_PLATFORM_AUTH, "平台 userToken 无效或已过期", res.status)
            429 -> throw DsException(DsHttp.ERR_PLATFORM_RATE_LIMITED, "平台接口限流，稍后再试", res.status)
        }
        if (res.status != 200) throw DsException(DsHttp.ERR_PLATFORM_FAILED, "平台接口 HTTP ${res.status}", res.status)
        return res
    }

    private fun platformJson(url: String): JSONObject {
        val res = platformGet(url)
        val json = runCatching { JSONObject(res.text) }.getOrElse {
            throw DsException(DsHttp.ERR_PLATFORM_FAILED, "平台接口返回非 JSON（可能需要 Cookie）")
        }
        val code = if (json.has("code")) json.optInt("code", 0) else 0
        if (code != 0) throw DsException(DsHttp.ERR_PLATFORM_FAILED, "平台接口错误：${json.optString("msg", "code=$code")}")
        return json
    }

    private fun fetchUsage(keys: List<ApiKeyEntry>): JSONObject {
        val now = Calendar.getInstance()
        val year = now.get(Calendar.YEAR)
        val month = now.get(Calendar.MONTH) + 1

        val amountJson = platformJson("$USAGE_AMOUNT_URL?month=$month&year=$year")
        val costJson = platformJson("$USAGE_COST_URL?month=$month&year=$year")
        val monthly = UsageParser.parseMonthly(amountJson, costJson, year, month)

        val out = JSONObject()
            .put("year", year)
            .put("month", month)
            .put("currency", monthly.currency)
            .put("monthTotal", monthly.total.toJson())

        val modelArr = JSONArray()
        monthly.models.forEach { m ->
            modelArr.put(JSONObject().put("model", m.model).put("usage", m.bucket.toJson()))
        }
        out.put("models", modelArr)

        val dayArr = JSONArray()
        monthly.days.forEach { d ->
            dayArr.put(
                JSONObject()
                    .put("date", d.date)
                    .put("tokens", d.tokens)
                    .put("requests", d.requests)
                    .put("cost", round6(d.cost))
            )
        }
        out.put("days", dayArr)

        // 今日（本地时区 0 点起），走 export 窗口；失败不阻断整页
        try {
            val today = fetchTodayUsage()
            out.put("today", today.toJson())
        } catch (e: DsException) {
            out.put("todayError", JSONObject().put("code", e.code).put("message", e.message ?: ""))
        }

        // 分 key 用量：走 export 导出本自然月 CSV
        try {
            val rows = fetchMonthExportRows()
            val todayUtc = utcToday()
            val keyArr = JSONArray()
            val csvKeys = UsageParser.distinctKeyNames(rows)
            val names = LinkedHashSet<String>()
            csvKeys.forEach { names.add(it) }
            // 未出现在 CSV 里的已配置 key 也列出（显示 0），便于对照
            keys.forEach { entry -> if (names.none { it == entry.name }) names.add(entry.name) }
            for (name in names) {
                val summary = UsageParser.summarizeRows(rows, todayUtc, name)
                val configured = keys.firstOrNull { it.name == name }
                val modelArr2 = JSONArray()
                summary.models.forEach { m ->
                    modelArr2.put(JSONObject().put("model", m.model).put("usage", m.bucket.toJson()))
                }
                keyArr.put(
                    JSONObject()
                        .put("name", name)
                        .put("configuredId", configured?.id ?: JSONObject.NULL)
                        .put("hasKey", configured != null)
                        .put("month", summary.month.toJson())
                        .put("today", summary.today.toJson())
                        .put("models", modelArr2)
                )
            }
            out.put("perKey", keyArr)
            out.put("perKeyTracked", true)
        } catch (e: DsException) {
            out.put("perKeyTracked", false)
            out.put("perKeyError", JSONObject().put("code", e.code).put("message", e.message ?: ""))
        }

        return out
    }

    /** 今日用量：export 接口的本地时区窗口（今天 0 点 → 下一个整点）。 */
    private fun fetchTodayUsage(): UsageBucket {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val start = cal.timeInMillis / 1000
        val nowSec = System.currentTimeMillis() / 1000
        val nextHour = ((nowSec + 3599) / 3600) * 3600
        val end = maxOf(nextHour, start + 3600)
        val rows = fetchExportRows(start, end)
        return UsageParser.summarizeRows(rows, utcToday(), null).month
    }

    private fun fetchMonthExportRows(): List<UsageParser.CsvRow> {
        val cal = Calendar.getInstance()
        cal.set(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val start = cal.timeInMillis / 1000
        val next = Calendar.getInstance()
        next.timeInMillis = cal.timeInMillis
        next.add(Calendar.MONTH, 1)
        val end = next.timeInMillis / 1000
        return fetchExportRows(start, end)
    }

    private fun fetchExportRows(start: Long, end: Long): List<UsageParser.CsvRow> {
        val res = platformGet("$USAGE_EXPORT_URL?start=$start&end=$end&tz=0")
        val csv = extractAmountCsv(res.body)
        return UsageParser.parseCsv(csv)
    }

    private fun extractAmountCsv(zip: ByteArray): String {
        var amountCsv: String? = null
        var fallback: String? = null
        try {
            ZipInputStream(ByteArrayInputStream(zip)).use { zin ->
                var entry = zin.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory && entry.name.lowercase().endsWith(".csv")) {
                        val out = ByteArrayOutputStream()
                        val buf = ByteArray(16 * 1024)
                        var total = 0
                        while (true) {
                            val n = zin.read(buf)
                            if (n <= 0) break
                            total += n
                            if (total > MAX_CSV_BYTES) throw DsException(DsHttp.ERR_INVALID_RESPONSE, "导出文件过大")
                            out.write(buf, 0, n)
                        }
                        val text = out.toString("UTF-8")
                        if (entry.name.lowercase().contains("amount")) { amountCsv = text } else if (fallback == null) fallback = text
                    }
                    zin.closeEntry()
                    entry = zin.nextEntry
                }
            }
        } catch (t: DsException) {
            throw t
        } catch (t: Throwable) {
            throw DsException(DsHttp.ERR_INVALID_RESPONSE, "导出 zip 解析失败")
        }
        return amountCsv ?: fallback ?: throw DsException(DsHttp.ERR_INVALID_RESPONSE, "导出 zip 中未找到 CSV")
    }

    companion object {
        const val SNAPSHOT_VERSION = 1
        const val BALANCE_URL = "https://api.deepseek.com/user/balance"
        const val USAGE_AMOUNT_URL = "https://platform.deepseek.com/api/v0/usage/amount"
        const val USAGE_COST_URL = "https://platform.deepseek.com/api/v0/usage/cost"
        const val USAGE_EXPORT_URL = "https://platform.deepseek.com/api/v0/usage/export"
        const val UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        private const val MAX_CSV_BYTES = 32 * 1024 * 1024

        fun utcToday(): String {
            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            return fmt.format(Date())
        }
    }
}

/** 演示数据：未配置凭据时也能看界面。全部为虚构数字。 */
object DemoData {
    fun snapshot(): JSONObject {
        val infos = JSONArray().put(
            JSONObject()
                .put("currency", "CNY")
                .put("totalBalance", 42.80)
                .put("grantedBalance", 2.80)
                .put("toppedUpBalance", 40.00)
        )
        val balance = JSONObject().put("isAvailable", true).put("infos", infos)

        val monthTotal = JSONObject()
            .put("tokens", 12_480_000L).put("cacheHit", 8_900_000L).put("cacheMiss", 2_180_000L)
            .put("output", 1_400_000L).put("requests", 3_640L).put("cost", 18.4271)
        val today = JSONObject()
            .put("tokens", 486_000L).put("cacheHit", 352_000L).put("cacheMiss", 94_000L)
            .put("output", 40_000L).put("requests", 128L).put("cost", 0.7124)

        val models = JSONArray()
            .put(JSONObject().put("model", "deepseek-chat").put("usage", JSONObject()
                .put("tokens", 9_120_000L).put("cacheHit", 6_700_000L).put("cacheMiss", 1_520_000L)
                .put("output", 900_000L).put("requests", 2_640L).put("cost", 12.8172)))
            .put(JSONObject().put("model", "deepseek-reasoner").put("usage", JSONObject()
                .put("tokens", 3_360_000L).put("cacheHit", 2_200_000L).put("cacheMiss", 660_000L)
                .put("output", 500_000L).put("requests", 1_000L).put("cost", 5.6099)))

        val days = JSONArray()
        for (i in 1..14) {
            days.put(
                JSONObject()
                    .put("date", String.format(Locale.US, "2026-10-%02d", i))
                    .put("tokens", 300_000L + i * 41_000L)
                    .put("requests", 90L + i * 7)
                    .put("cost", round6(0.9 + i * 0.137))
            )
        }

        val perKey = JSONArray()
            .put(keyBlock("prod-backend", 7_400_000L, 11.2400, 2_160L, 210_000L, 0.4200, 61L))
            .put(keyBlock("dev-local", 3_280_000L, 4.8100, 1_020L, 160_000L, 0.2100, 42L))
            .put(keyBlock("ci-pipeline", 1_800_000L, 2.3771, 460L, 116_000L, 0.0824, 25L))

        val usage = JSONObject()
            .put("year", 2026)
            .put("month", 10)
            .put("currency", "CNY")
            .put("monthTotal", monthTotal)
            .put("models", models)
            .put("days", days)
            .put("today", today)
            .put("perKey", perKey)
            .put("perKeyTracked", true)

        val keyChecks = JSONArray()
            .put(JSONObject().put("id", "demo-1").put("name", "prod-backend").put("masked", "sk-ab…9f2c")
                .put("ok", true).put("balance", balance))

        return JSONObject()
            .put("version", DsRepository.SNAPSHOT_VERSION)
            .put("fetchedAt", System.currentTimeMillis())
            .put("currency", "CNY")
            .put("demo", true)
            .put("balance", balance)
            .put("keyChecks", keyChecks)
            .put("usage", usage)
    }

    private fun keyBlock(name: String, tokens: Long, cost: Double, requests: Long, todayTokens: Long, todayCost: Double, todayReqs: Long): JSONObject =
        JSONObject()
            .put("name", name)
            .put("hasKey", true)
            .put("month", JSONObject()
                .put("tokens", tokens).put("cacheHit", tokens / 3 * 2).put("cacheMiss", tokens / 4)
                .put("output", tokens / 10).put("requests", requests).put("cost", cost))
            .put("today", JSONObject()
                .put("tokens", todayTokens).put("cacheHit", todayTokens / 3 * 2).put("cacheMiss", todayTokens / 4)
                .put("output", todayTokens / 10).put("requests", todayReqs).put("cost", todayCost))
            .put("models", JSONArray())
}
