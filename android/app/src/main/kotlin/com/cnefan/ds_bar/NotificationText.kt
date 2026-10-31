package com.cnefan.ds_bar

import org.json.JSONObject
import java.util.Locale

/**
 * 通知文案生成。纯函数，不依赖 Android API，便于在 JVM 单测里直接验证。
 *
 * 系统通知样式由 SystemUI 排版，我们只能控制标题、正文、展开文本三处文字。
 * 因此信息密度靠「层级化措辞」实现，而不是靠改布局：
 * 标题只放余额，正文放今日，展开文本放四项指标 + 状态 + 更新时间。
 */
object NotificationText {

    /** 生成结果。三个字段分别对应 setContentTitle / setContentText / BigTextStyle。 */
    data class Content(
        val title: String,
        val text: String,
        val big: String,
        /** 供无障碍与排障：出现异常时的简短原因，正常为空。 */
        val statusHint: String = "",
        // 以下字段供自定义布局直接绑定，与 big 同源，避免布局层二次解析
        val monthCost: String = "",
        val monthTokens: String = "",
        val monthRequests: String = "",
        val cacheRate: String = "",
        val updated: String = "",
        val chip: String = ""
    )

    private fun statusOf(snapshot: JSONObject): String {
        val balanceErr = snapshot.optJSONObject("balanceError")?.optString("code")
        val usageErr = snapshot.optJSONObject("usageError")?.optString("code")
        return when {
            balanceErr == "auth_failed" -> "API Key 无效"
            balanceErr == "missing_credential" -> "未配置 API Key"
            usageErr == "platform_auth" -> "userToken 已过期"
            snapshot.optJSONObject("usageError") != null -> "用量未接入"
            balanceErr != null -> "余额获取失败"
            else -> ""
        }
    }

    fun build(snapshot: JSONObject?, nowMillis: Long = 0L): Content {
        if (snapshot == null) {
            return Content(
                title = "未同步",
                text = "点按打开 App 同步",
                big = "还没有取到数据。\n点按打开 App，下拉刷新或点右上角同步。",
                statusHint = "尚未同步"
            )
        }

        val currency = snapshot.optString("currency", "CNY")
        val sym = Fmt.currencySymbol(currency)
        val info = snapshot.optJSONObject("balance")?.optJSONArray("infos")?.optJSONObject(0)
        val usage = snapshot.optJSONObject("usage")
        val today = usage?.optJSONObject("today")
        val month = usage?.optJSONObject("monthTotal")
        val status = statusOf(snapshot)
        val demo = snapshot.optBoolean("demo", false)

        val todayCost = today?.optDouble("cost", 0.0) ?: 0.0
        val todayTokens = today?.optLong("tokens", 0L) ?: 0L
        val todayReq = today?.optLong("requests", 0L) ?: 0L
        val monthCost = month?.optDouble("cost", 0.0) ?: 0.0
        val monthTokens = month?.optLong("tokens", 0L) ?: 0L
        val monthReq = month?.optLong("requests", 0L) ?: 0L
        val hit = month?.optLong("cacheHit", 0L) ?: 0L
        val miss = month?.optLong("cacheMiss", 0L) ?: 0L
        val rate = Fmt.cacheHitRate(hit, miss)

        // 标题：只放余额。拿不到就用占位符，绝不写「余额不足」（未配置 ≠ 不足）。
        val title = if (info == null) {
            Fmt.DASH
        } else {
            sym + Fmt.money(info.optDouble("totalBalance", 0.0))
        }

        // 正文：今日支出。用量拿不到时改述原因，不显示 0。
        val text = when {
            today != null && (todayCost > 0.0 || todayTokens > 0L) ->
                "今日 " + Fmt.spent(todayCost) + " · " + Fmt.tokens(todayTokens)
            status.isNotEmpty() -> status
            else -> "今日 " + Fmt.spent(todayCost) + " · " + Fmt.tokens(todayTokens)
        }

        // 展开：四项指标一行，状态与时间一行。
        val metrics = StringBuilder()
        metrics.append("本月 ").append(sym).append(Fmt.money(monthCost))
        metrics.append(" · ").append(Fmt.tokens(monthTokens)).append(" tokens")
        metrics.append(" · ").append(Fmt.count(monthReq)).append(" 次")
        if (rate != null) metrics.append(" · 命中 ").append(Fmt.percent(rate))

        val tail = StringBuilder()
        if (today != null) {
            tail.append("今日 ").append(Fmt.tokens(todayTokens)).append(" tokens")
            tail.append(" · ").append(Fmt.count(todayReq)).append(" 次")
        } else {
            tail.append("今日用量不可用")
        }

        val flags = mutableListOf<String>()
        if (demo) flags.add("演示数据")
        if (status.isNotEmpty()) flags.add(status)
        info?.let { i ->
            val available = snapshot.optJSONObject("balance")?.optBoolean("isAvailable", false) ?: false
            if (!available) flags.add("余额不足")
            val topped = i.optDouble("toppedUpBalance", Double.NaN)
            val granted = i.optDouble("grantedBalance", Double.NaN)
            if (!topped.isNaN() || !granted.isNaN()) {
                flags.add(
                    "充 " + sym + Fmt.money(if (topped.isNaN()) 0.0 else topped) +
                        " / 赠 " + sym + Fmt.money(if (granted.isNaN()) 0.0 else granted)
                )
            }
        }

        val ts = if (nowMillis > 0L) nowMillis else snapshot.optLong("fetchedAt", 0L)
        val timeLine = if (ts > 0) {
            java.text.SimpleDateFormat("HH:mm", Locale.getDefault()).format(java.util.Date(ts)) + " 更新"
        } else {
            "未同步"
        }

        val big = buildString {
            append(metrics)
            append('\n')
            append(tail)
            if (flags.isNotEmpty()) {
                append('\n')
                append(flags.joinToString(" · "))
            }
            append('\n')
            append(timeLine)
        }

        val chipText = when {
            demo -> "演示数据"
            status.isNotEmpty() -> status
            else -> ""
        }
        return Content(
            title = title,
            text = text,
            big = big,
            statusHint = status,
            monthCost = sym + Fmt.money(monthCost),
            monthTokens = Fmt.tokens(monthTokens),
            monthRequests = Fmt.count(monthReq),
            cacheRate = Fmt.percent(rate),
            updated = timeLine,
            chip = chipText
        )
    }
}
