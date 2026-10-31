package com.cnefan.ds_bar

import android.content.Context
import org.json.JSONObject
import java.util.Locale

object Fmt {

    const val MINUS = "\u2212" // U+2212 真减号，比 ASCII 连字符更短、更居中

    /** 与 Dart 侧 Fmt.money 保持同一分级，界面与通知不会出现两种写法。 */
    fun money(v: Double): String {
        if (!v.isFinite()) return "0.00"
        val mag = Math.abs(v)
        val sign = if (v < 0) MINUS else ""
        return sign + when {
            mag >= 10000 -> String.format(Locale.US, "%,.0f", mag)
            mag >= 1000 -> String.format(Locale.US, "%,.1f", mag)
            mag >= 100 -> String.format(Locale.US, "%.1f", mag)
            else -> String.format(Locale.US, "%.2f", mag)
        }
    }

    /** 磁贴用缩位：余额固定 1 位小数，省掉字符宽度。 */
    fun moneyCompact(v: Double): String {
        if (!v.isFinite()) return "0.0"
        val mag = Math.abs(v)
        val sign = if (v < 0) MINUS else ""
        return sign + when {
            mag >= 10000 -> String.format(Locale.US, "%,.0f", mag)
            mag >= 1000 -> String.format(Locale.US, "%,.1f", mag)
            else -> String.format(Locale.US, "%.1f", mag)
        }
    }

    /**
     * 今日支出：加负号表达「已花掉」，两位小数。
     * 数值为 0 时返回 "0.00" 不带负号，避免 0 被读成负债。
     */
    fun spent(v: Double): String {
        if (!v.isFinite() || v <= 0) return "0.00"
        return MINUS + money(v)
    }

    /**
     * 磁贴副行：去币种符号只留数字，字符数减半。
     * 例如 -0.71 → "−0.71"，0 → "0.00"。
     */
    fun spentBare(v: Double): String {
        if (!v.isFinite() || v <= 0) return "0.00"
        return MINUS + String.format(Locale.US, "%.2f", v)
    }

    fun tokens(v: Long): String = when {
        v >= 1_000_000_000L -> String.format(Locale.US, "%.2fB", v / 1_000_000_000.0)
        v >= 1_000_000L -> String.format(Locale.US, "%.2fM", v / 1_000_000.0)
        v >= 1_000L -> String.format(Locale.US, "%.1fK", v / 1_000.0)
        else -> v.toString()
    }

    fun count(v: Long): String = String.format(Locale.US, "%,d", v)

    /** 缓存命中率：命中 /（命中 + 未命中）。无输入时返回 null。 */
    fun cacheHitRate(hit: Long, miss: Long): Double? {
        val total = hit + miss
        return if (total <= 0) null else hit.toDouble() / total
    }

    /** 百分比，1 位小数，无意义时返回 "—"。 */
    fun percent(ratio: Double?): String =
        if (ratio == null || !ratio.isFinite()) "\u2014"
        else String.format(Locale.US, "%.1f%%", ratio * 100)

    fun currencySymbol(currency: String?): String = if (currency == "USD") "$" else "¥"

    /** 占位符：拿不到数值时统一用长破折号，不用 0，避免误读为真实值。 */
    const val DASH = "\u2014\u2014"
}

/** 统一刷新流程：取数 → 落盘 → 更新通知与磁贴。 */
object DsRefresh {

    fun perform(context: Context): JSONObject? {
        val prefs = DsPrefs(context)
        var snapshot: JSONObject? = null
        try {
            snapshot = DsRepository(context).refresh()
        } catch (t: Throwable) {
            snapshot = prefs.cachedSnapshot?.let { runCatching { JSONObject(it) }.getOrNull() }
        }
        if (prefs.notifyEnabled) {
            BalanceNotification.show(context, snapshot)
        } else {
            BalanceNotification.cancel(context)
        }
        runCatching { BalanceTileService.requestUpdate(context) }
        return snapshot
    }
}
