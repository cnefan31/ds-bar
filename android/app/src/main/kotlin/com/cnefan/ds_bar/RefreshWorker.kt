package com.cnefan.ds_bar

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/** 后台定时刷新：取数、更新缓存、刷新通知与磁贴。 */
class RefreshWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        return try {
            DsRefresh.perform(applicationContext)
            Result.success()
        } catch (t: Throwable) {
            Result.retry()
        }
    }
}

object RefreshScheduler {

    private const val WORK_NAME = "ds_bar_periodic_refresh"

    fun schedule(context: Context, minutes: Int) {
        val interval = minutes.coerceIn(15, 1440).toLong()
        val request = PeriodicWorkRequestBuilder<RefreshWorker>(interval, TimeUnit.MINUTES)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()
        runCatching {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }
    }

    fun cancel(context: Context) {
        runCatching { WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME) }
    }
}
