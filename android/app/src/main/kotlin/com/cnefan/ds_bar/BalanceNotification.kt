package com.cnefan.ds_bar

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject

/**
 * 常驻通知：展示余额与今日消费。
 */
object BalanceNotification {

    const val CHANNEL_ID = "ds_bar_balance"
    const val NOTIFICATION_ID = 1001

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

    fun build(context: Context, snapshot: JSONObject?): Notification {
        ensureChannel(context)
        val content = NotificationText.build(snapshot)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_balance)
            .setContentTitle(content.title)
            .setContentText(content.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content.big))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(contentIntent(context))

        val refreshIntent = Intent(context, RefreshActionReceiver::class.java).apply {
            action = RefreshActionReceiver.ACTION_REFRESH
        }
        val refreshFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val refreshPending = PendingIntent.getBroadcast(context, 1, refreshIntent, refreshFlags)
        builder.addAction(0, "刷新", refreshPending)

        return builder.build()
    }

    fun show(context: Context, snapshot: JSONObject?) {
        ensureChannel(context)
        if (!canNotify(context)) return
        runCatching {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, build(context, snapshot))
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
