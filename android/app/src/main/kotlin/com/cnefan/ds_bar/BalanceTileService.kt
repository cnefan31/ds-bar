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
        val sym = if (currency == "USD") "$" else "¥"

        tile.state = if (snapshot == null) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE

        val label: String
        val subtitle: String?
        if (info != null) {
            label = "$sym${Fmt.money(info.optDouble("totalBalance", 0.0))}"
            val today = snapshot?.optJSONObject("usage")?.optJSONObject("today")
            subtitle = today?.let { "今日 $sym${Fmt.money(it.optDouble("cost", 0.0))}" }
                ?: "DeepSeek 余额"
        } else {
            label = "DeepSeek"
            subtitle = if (prefs.keys().isEmpty()) "未配置" else "点按刷新"
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
