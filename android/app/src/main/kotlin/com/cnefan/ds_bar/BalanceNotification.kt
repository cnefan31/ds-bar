package com.cnefan.ds_bar

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * 常驻通知：展示余额与今日消费。
 */
object BalanceNotification {

    const val CHANNEL_ID = "ds_bar_balance"
    /**
     * 通知 id。
     *
     * 曾用 1001，但在本机被 EMUI 标记为 persist 后反复清理（日志：add 后即 remove，
     * 且仅该 id 受影响、同通道其它 id 正常）。改用 1101，与诊断验证通过的 id 一致。
     */
    const val NOTIFICATION_ID = 1101

    /** 深浅色判定：读系统 uiMode，两套布局各自带死文字色，避免运行时改色。 */
    private fun isNight(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "余额与用量",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "常驻显示 DeepSeek 账户余额与今日消费"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            if (granted != PackageManager.PERMISSION_GRANTED) return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, 0, intent, flags)
    }

    private fun bindCollapsed(rv: RemoteViews, c: NotificationText.Content) {
        rv.setTextViewText(R.id.n_balance, c.title)
        rv.setTextViewText(R.id.n_today, c.text)
        rv.setViewVisibility(
            R.id.n_flag,
            if (c.statusHint.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
        )
    }

    private fun bindExpanded(rv: RemoteViews, c: NotificationText.Content) {
        rv.setTextViewText(R.id.n_balance, c.title)
        rv.setTextViewText(R.id.n_today, c.text)
        rv.setTextViewText(R.id.n_month_cost, c.monthCost)
        rv.setTextViewText(R.id.n_month_tokens, c.monthTokens)
        rv.setTextViewText(R.id.n_month_requests, c.monthRequests)
        rv.setTextViewText(R.id.n_cache_rate, c.cacheRate)
        rv.setTextViewText(R.id.n_updated, c.updated)
        if (c.chip.isEmpty()) {
            rv.setViewVisibility(R.id.n_chip, android.view.View.GONE)
        } else {
            rv.setViewVisibility(R.id.n_chip, android.view.View.VISIBLE)
            rv.setTextViewText(R.id.n_chip, c.chip)
        }
    }

    fun build(context: Context, snapshot: JSONObject?): Notification {
        ensureChannel(context)
        val content = NotificationText.build(snapshot)

        val light = !isNight(context)
        // 直接引用 R.layout.*，不要缓存成 const：const 会在编译期内联，
        // 增量构建后可能与实际资源 id 不一致，导致 layoutId=0 而 inflate 失败。
        val collapsed = RemoteViews(
            context.packageName,
            if (light) R.layout.notification_collapsed_light else R.layout.notification_collapsed
        )
        val expanded = RemoteViews(
            context.packageName,
            if (light) R.layout.notification_expanded_light else R.layout.notification_expanded
        )
        bindCollapsed(collapsed, content)
        bindExpanded(expanded, content)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_balance)
            .setContentTitle(content.title)
            .setContentText(content.text)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(contentIntent(context))

        // 通知栏不再放「刷新」按钮：点整卡进 App，手动刷新入口保留在磁贴与 App 内。
        return builder.build()
    }

    fun show(context: Context, snapshot: JSONObject?) {
        ensureChannel(context)
        if (!canNotify(context)) {
            android.util.Log.w("DsBarNotify", "skip: canNotify=false")
            return
        }
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, build(context, snapshot))
            android.util.Log.i("DsBarNotify", "notified id=$NOTIFICATION_ID")
        } catch (t: Throwable) {
            android.util.Log.e("DsBarNotify", "notify threw", t)
        }
    }

    fun cancel(context: Context) {
        runCatching { NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID) }
    }

    fun updateFromCache(context: Context, prefs: DsPrefs) {
        if (!prefs.notifyEnabled) {
            cancel(context)
            return
        }
        val snapshot = prefs.cachedSnapshot?.let { runCatching { JSONObject(it) }.getOrNull() }
        show(context, snapshot)
    }
}

/** 通知栏「刷新」按钮。 */
class RefreshActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_REFRESH) return
        val pending = goAsync()
        Thread {
            try {
                DsRefresh.perform(context)
            } catch (t: Throwable) {
                // 静默：失败信息会体现在通知文本的状态行
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        const val ACTION_REFRESH = "com.cnefan.ds_bar.action.REFRESH"
    }
}
