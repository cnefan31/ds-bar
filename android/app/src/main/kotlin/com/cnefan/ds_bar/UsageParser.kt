package com.cnefan.ds_bar

import org.json.JSONArray
import org.json.JSONObject

/**
 * 用量聚合结果。全部为「期间内」的合计值。
 */
class UsageBucket(
    var tokens: Long = 0,
    var cacheHit: Long = 0,
    var cacheMiss: Long = 0,
    var output: Long = 0,
    var requests: Long = 0,
    var cost: Double = 0.0
) {
    fun addTokens(type: String, amount: Long, price: Double) {
        when (type) {
            "request_count" -> requests += amount
            "input_cache_hit_tokens" -> { cacheHit += amount; tokens += amount; cost += price * amount }
            "input_cache_miss_tokens" -> { cacheMiss += amount; tokens += amount; cost += price * amount }
            "output_tokens" -> { output += amount; tokens += amount; cost += price * amount }
            // 平台月接口的 type 命名
            "PROMPT_CACHE_HIT_TOKEN" -> { cacheHit += amount; tokens += amount; cost += price * amount }
            "PROMPT_CACHE_MISS_TOKEN" -> { cacheMiss += amount; tokens += amount; cost += price * amount }
            "RESPONSE_TOKEN" -> { output += amount; tokens += amount; cost += price * amount }
            "REQUEST" -> requests += amount
        }
    }

    fun addCost(value: Double) { cost += value }

    fun merge(other: UsageBucket): UsageBucket {
        tokens += other.tokens
        cacheHit += other.cacheHit
        cacheMiss += other.cacheMiss
        output += other.output
        requests += other.requests
        cost += other.cost
        return this
    }

    fun toJson(): JSONObject = JSONObject()
        .put("tokens", tokens)
        .put("cacheHit", cacheHit)
        .put("cacheMiss", cacheMiss)
        .put("output", output)
        .put("requests", requests)
        .put("cost", round6(cost))
}

fun round6(v: Double): Double = Math.round(v * 1_000_000.0) / 1_000_000.0

/** 平台月接口（api/v0/usage/amount + usage/cost）的聚合结果。 */
class MonthUsage(
    val year: Int,
    val month: Int,
    val currency: String,
    val total: UsageBucket,
    val models: List<ModelUsage>,
    val days: List<DayUsage>
)

class ModelUsage(val model: String, val bucket: UsageBucket)
class DayUsage(val date: String, val tokens: Long, val requests: Long, val cost: Double)

object UsageParser {

    fun parseIntOrZero(v: Any?): Long = when (v) {
        null -> 0L
        is Number -> v.toLong()
        else -> v.toString().trim().toLongOrNull() ?: 0L
    }

    fun parseDoubleOrZero(v: Any?): Double = when (v) {
        null -> 0.0
        is Number -> v.toDouble()
        else -> v.toString().trim().toDoubleOrNull() ?: 0.0
    }

    /**
     * 合并 usage/amount 与 usage/cost 两个响应。
     * amount 给 token 与请求数；cost 给费用（以 amount 计价，单位与币种一致）。
     */
    fun parseMonthly(amountJson: JSONObject, costJson: JSONObject, year: Int, month: Int): MonthUsage {
        val amountBiz = amountJson.optJSONObject("data")?.optJSONObject("biz_data")
        val costBizRaw = costJson.optJSONObject("data")?.opt("biz_data")
        val costBiz: JSONObject? = when (costBizRaw) {
            is JSONObject -> costBizRaw
            is JSONArray -> costBizRaw.optJSONObject(0)
            else -> null
        }
        val currency = costBiz?.optString("currency")?.ifBlank { "CNY" } ?: "CNY"

        val total = UsageBucket()
        val modelMap = LinkedHashMap<String, UsageBucket>()

        amountBiz?.optJSONArray("total")?.let { arr ->
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val model = item.optString("model")
                val bucket = UsageBucket()
                val usage = item.optJSONArray("usage") ?: continue
                for (j in 0 until usage.length()) {
                    val u = usage.optJSONObject(j) ?: continue
                    bucket.addTokens(u.optString("type"), parseIntOrZero(u.opt("amount")), 0.0)
                }
                total.merge(UsageBucket(bucket.tokens, bucket.cacheHit, bucket.cacheMiss, bucket.output, bucket.requests, 0.0))
                if (model.isNotEmpty()) modelMap[model] = bucket
            }
        }

        val modelCost = LinkedHashMap<String, Double>()
        costBiz?.optJSONArray("total")?.let { arr ->
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val model = item.optString("model")
                var c = 0.0
                val usage = item.optJSONArray("usage") ?: continue
                for (j in 0 until usage.length()) {
                    val u = usage.optJSONObject(j) ?: continue
                    if (u.optString("type") == "REQUEST") continue
                    c += parseDoubleOrZero(u.opt("amount"))
                }
                if (model.isNotEmpty()) modelCost[model] = (modelCost[model] ?: 0.0) + c
                total.addCost(c)
            }
        }

        val dayCost = LinkedHashMap<String, Double>()
        costBiz?.optJSONArray("days")?.let { arr ->
            for (i in 0 until arr.length()) {
                val d = arr.optJSONObject(i) ?: continue
                val date = d.optString("date")
                if (date.isEmpty()) continue
                var c = 0.0
                d.optJSONArray("data")?.let { data ->
                    for (k in 0 until data.length()) {
                        val item = data.optJSONObject(k) ?: continue
                        item.optJSONArray("usage")?.let { usage ->
                            for (j in 0 until usage.length()) {
                                val u = usage.optJSONObject(j) ?: continue
                                if (u.optString("type") == "REQUEST") continue
                                c += parseDoubleOrZero(u.opt("amount"))
                            }
                        }
                    }
                }
                dayCost[date] = (dayCost[date] ?: 0.0) + c
            }
        }

        val dayTokens = LinkedHashMap<String, Long>()
        val dayRequests = LinkedHashMap<String, Long>()
        amountBiz?.optJSONArray("days")?.let { arr ->
            for (i in 0 until arr.length()) {
                val d = arr.optJSONObject(i) ?: continue
                val date = d.optString("date")
                if (date.isEmpty()) continue
                var tk = 0L
                var rq = 0L
                d.optJSONArray("data")?.let { data ->
                    for (k in 0 until data.length()) {
                        val item = data.optJSONObject(k) ?: continue
                        item.optJSONArray("usage")?.let { usage ->
                            for (j in 0 until usage.length()) {
                                val u = usage.optJSONObject(j) ?: continue
                                val n = parseIntOrZero(u.opt("amount"))
                                if (u.optString("type") == "REQUEST") rq += n else tk += n
                            }
                        }
                    }
                }
                dayTokens[date] = (dayTokens[date] ?: 0L) + tk
                dayRequests[date] = (dayRequests[date] ?: 0L) + rq
            }
        }

        val models = modelMap.map { (model, bucket) ->
            ModelUsage(model, UsageBucket(bucket.tokens, bucket.cacheHit, bucket.cacheMiss, bucket.output, bucket.requests, modelCost[model] ?: 0.0))
        }.sortedByDescending { it.bucket.tokens }

        val days = dayTokens.keys.union(dayCost.keys).sorted().map { date ->
            DayUsage(date, dayTokens[date] ?: 0L, dayRequests[date] ?: 0L, dayCost[date] ?: 0.0)
        }

        return MonthUsage(year, month, currency, total, models, days)
    }

    /** 解析 usage/export 返回的 CSV 行（列：utc_date, api_key_name, model, type, amount, price）。 */
    fun parseCsv(text: String): List<CsvRow> {
        val lines = text.removePrefix("\uFEFF").split('\n').map { it.trimEnd('\r') }.filter { it.isNotBlank() }
        if (lines.size < 2) return emptyList()
        val headers = splitCsvLine(lines[0])
        val out = ArrayList<CsvRow>(lines.size - 1)
        for (i in 1 until lines.size) {
            val values = splitCsvLine(lines[i])
            if (values.isEmpty()) continue
            fun col(name: String): String {
                val idx = headers.indexOf(name)
                return if (idx >= 0 && idx < values.size) values[idx] else ""
            }
            out.add(
                CsvRow(
                    date = normalizeDate(col("utc_date")),
                    apiKeyName = col("api_key_name"),
                    model = col("model"),
                    type = col("type"),
                    amount = parseIntOrZero(col("amount")),
                    price = parseDoubleOrZero(col("price"))
                )
            )
        }
        return out
    }

    class CsvRow(
        val date: String,
        val apiKeyName: String,
        val model: String,
        val type: String,
        val amount: Long,
        val price: Double
    )

    fun normalizeDate(v: String): String =
        if (v.length == 8 && !v.contains("-")) "${v.substring(0, 4)}-${v.substring(4, 6)}-${v.substring(6, 8)}" else v

    fun splitCsvLine(line: String): List<String> {
        val result = ArrayList<String>()
        val sb = StringBuilder()
        var inQuotes = false
        var i = 0
        while (i < line.length) {
            val ch = line[i]
            if (inQuotes) {
                if (ch == '"' && i + 1 < line.length && line[i + 1] == '"') { sb.append('"'); i++ }
                else if (ch == '"') inQuotes = false
                else sb.append(ch)
            } else {
                when (ch) {
                    '"' -> inQuotes = true
                    ',' -> { result.add(sb.toString()); sb.setLength(0) }
                    else -> sb.append(ch)
                }
            }
            i++
        }
        result.add(sb.toString())
        return result
    }

    /** 按 api_key_name 汇总 CSV 行。keyFilter 为 null 表示全部 key。 */
    fun summarizeRows(rows: List<CsvRow>, todayUtc: String, keyFilter: String?): KeyUsageSummary {
        val bucket = UsageBucket()
        val todayBucket = UsageBucket()
        val modelTokens = LinkedHashMap<String, UsageBucket>()
        for (row in rows) {
            if (keyFilter != null && row.apiKeyName != keyFilter) continue
            bucket.addTokens(row.type, row.amount, row.price)
            if (row.date == todayUtc) todayBucket.addTokens(row.type, row.amount, row.price)
            if (row.type != "request_count" && row.model.isNotEmpty()) {
                modelTokens.getOrPut(row.model) { UsageBucket() }.addTokens(row.type, row.amount, row.price)
            }
        }
        return KeyUsageSummary(
            month = bucket,
            today = todayBucket,
            models = modelTokens.map { (m, b) -> ModelUsage(m, b) }.sortedByDescending { it.bucket.tokens }
        )
    }

    class KeyUsageSummary(val month: UsageBucket, val today: UsageBucket, val models: List<ModelUsage>)

    fun distinctKeyNames(rows: List<CsvRow>): List<String> {
        val seen = LinkedHashSet<String>()
        rows.forEach { if (it.apiKeyName.isNotBlank()) seen.add(it.apiKeyName) }
        return seen.toList()
    }
}
