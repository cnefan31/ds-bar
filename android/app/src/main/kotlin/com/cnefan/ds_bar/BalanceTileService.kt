package com.cnefan.ds_bar

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import org.json.JSONObject

/**
 * 快速设置磁贴：点按刷新，副标题显示余额。
 */
@RequiresApi(Build.VERSION_CODES.N)
class BalanceTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val tile = qsTile ?: return
        tile.state = Tile.STATE_UNAVAILABLE
        tile.updateTile()
        Thread {
            try {
                DsRefresh.perform(applicationContext)
            } finally {
                updateTileOnMain()
            }
        }.start()
    }

    private fun updateTileOnMain() {
        android.os.Handler(mainLooper).post { updateTile() }
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val prefs = DsPrefs(this)
        val snapshot = prefs.cachedSnapshot?.let { runCatching { JSONObject(it) }.getOrNull() }
        val info = snapshot?.optJSONObject("balance")?.optJSONArray("infos")?.optJSONObject(0)
        val currency = snapshot?.optString("currency", "CNY") ?: "CNY"
        val sym = Fmt.currencySymbol(currency)

        tile.state = if (snapshot == null) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE

        // 主行档位：余额；副行：今日消费。两个数层级必须拉开，否则会被读成一个数。
        val label: String
        val subtitle: String?
        when {
            info != null -> {
                label = sym + Fmt.moneyCompact(info.optDouble("totalBalance", 0.0))
                val todayObj = snapshot?.optJSONObject("usage")?.optJSONObject("today")
                val cost = todayObj?.optDouble("cost", 0.0) ?: 0.0
                subtitle = when {
                    todayObj == null -> "用量未接入"
                    cost <= 0.0 -> "今日 0.00"
                    // 副行去掉币种符号，字符数减半。
                    else -> "今日 " + Fmt.spentBare(cost)
                }
            }
            prefs.keys().isEmpty() -> {
                label = Fmt.DASH
                subtitle = "未配置 Key"
            }
            else -> {
                label = Fmt.DASH
                subtitle = when (snapshot?.optJSONObject("balanceError")?.optString("code")) {
                    "auth_failed" -> "Key 无效"
                    "timeout" -> "请求超时"
                    null -> "点按刷新"
                    else -> "获取失败"
                }
            }
        }

        tile.label = label
        // setSubtitle 自 API 29 起可用，低版本只显示 label。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle
        }
        runCatching { tile.updateTile() }
    }

    companion object {
        fun requestUpdate(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            runCatching {
                requestListeningState(
                    context,
                    ComponentName(context, BalanceTileService::class.java)
                )
            }
        }
    }
}
