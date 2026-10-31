package com.cnefan.ds_bar

import android.content.Context
import org.json.JSONObject
import java.util.Locale

object Fmt {

    /** 与 Dart 侧 Fmt.money 保持同一分级，界面与通知不会出现两种写法。 */
    fun money(v: Double): String {
        if (!v.isFinite()) return "0.00"
        val mag = Math.abs(v)
        return when {
            mag >= 10000 -> String.format(Locale.US, "%,.0f", v)
            mag >= 1000 -> String.format(Locale.US, "%,.1f", v)
            mag >= 100 -> String.format(Locale.US, "%.1f", v)
            else -> String.format(Locale.US, "%.2f", v)
        }
    }

    fun tokens(v: Long): String = when {
        v >= 1_000_000_000L -> String.format(Locale.US, "%.2fB", v / 1_000_000_000.0)
        v >= 1_000_000L -> String.format(Locale.US, "%.2fM", v / 1_000_000.0)
        v >= 1_000L -> String.format(Locale.US, "%.1fK", v / 1_000.0)
        else -> v.toString()
    }
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
