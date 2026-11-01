package com.cnefan.ds_bar

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import java.util.concurrent.TimeUnit

/**
 * 后台定时刷新：取数、更新缓存、刷新通知与磁贴。
 *
 * 用平台 JobScheduler，而不是 WorkManager。WorkManager 会连带引入
 * Room、SQLite 与 kotlinx-coroutines，dex 多出约 450KB，而本项目一个都用不上——
 * 这里只需要「每 N 分钟跑一次、有网才跑、重启后仍有效」。
 * JobScheduler 自 API 21 起可用，minSdk 24 无需额外兼容。
 */
class RefreshJobService : JobService() {

    override fun onStartJob(params: JobParameters?): Boolean {
        Thread {
            try {
                DsRefresh.perform(applicationContext)
            } catch (t: Throwable) {
                // 失败时沿用上一次缓存，通知文本里的状态行会体现实情
            } finally {
                jobFinished(params, false)
            }
        }.start()
        // 返回 true 表示任务在本线程之外继续，必须显式调用 jobFinished。
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = true
}

object RefreshScheduler {

    /** 固定 id：同一时刻只允许一个刷新任务。与通知 id 无关。 */
    private const val JOB_ID = 3001

    fun schedule(context: Context, minutes: Int) {
        val interval = minutes.coerceIn(15, 1440).toLong()
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        // 参数没变就不重建，避免每次打开 App 都把计时器归零。
        val existing = runCatching { scheduler.getPendingJob(JOB_ID) }.getOrNull()
        if (existing != null && existing.intervalMillis == TimeUnit.MINUTES.toMillis(interval)) return

        val info = JobInfo.Builder(JOB_ID, ComponentName(context, RefreshJobService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(TimeUnit.MINUTES.toMillis(interval))
            // 重启后仍然有效（依赖 RECEIVE_BOOT_COMPLETED，已在 manifest 声明）。
            .setPersisted(true)
            .build()
        runCatching { scheduler.schedule(info) }
    }

    fun cancel(context: Context) {
        runCatching { context.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID) }
    }
}
