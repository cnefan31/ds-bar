package com.cnefan.ds_bar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 登录期间的前台服务，唯一职责是让进程活着。
 *
 * 为什么需要：用户点「浏览器登录」后，浏览器被拉到前台，本应用退到后台。
 * 华为 EMUI（以及多数国产 ROM、Android 12+ 的 cached-app 冻结）会**冻结后台进程**，
 * 此时浏览器带着 code 跳回 127.0.0.1 会连得上但没人应答，登录必然超时。
 * 实测（HLK-AL10）：前台时回调服务正常返回 404/400，退到后台后无任何响应。
 *
 * 前台服务挂一条低优先级通知即可避免被冻结，流程结束立即 stopSelf。
 * 不引入新依赖，只加 FOREGROUND_SERVICE(+DATA_SYNC) 权限与一个 service 声明。
 */
class LoginKeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel(this)
        val notification = build(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // 不重启：登录是一次性交互，进程被杀就让它失败重试。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
        super.onDestroy()
    }

    companion object {
        const val CHANNEL_ID = "ds_bar_login"
        const val NOTIFICATION_ID = 1201

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "登录",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "浏览器授权期间保持登录流程存活"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }

        private fun build(context: Context): Notification {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            builder.setSmallIcon(R.drawable.ic_stat_balance)
                .setContentTitle("正在登录 DeepSeek")
                .setContentText("在浏览器完成授权后会自动返回")
                .setOngoing(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_PROGRESS)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                builder.setPriority(Notification.PRIORITY_MIN)
            }
            return builder.build()
        }

        fun start(context: Context) {
            runCatching {
                val intent = Intent(context, LoginKeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }

        fun stop(context: Context) {
            runCatching { context.stopService(Intent(context, LoginKeepAliveService::class.java)) }
        }
    }
}
