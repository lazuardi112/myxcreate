package com.example.myxcreate // Pastikan ini sesuai package project-mu

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * RestartWorker bertugas untuk menjalankan ForegroundService secara periodik
 * agar service bisa tetap berjalan di background.
 */
class RestartWorker(appContext: Context, workerParams: WorkerParameters) : Worker(appContext, workerParams) {

    override fun doWork(): Result {
        val ctx = applicationContext

        // Intent untuk memulai ForegroundService
        val serviceIntent = Intent(ctx, ForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.startForegroundService(serviceIntent)
        } else {
            ctx.startService(serviceIntent)
        }

        return Result.success()
    }

    companion object {
        /**
         * Schedule worker untuk memulai ForegroundService setelah delay tertentu
         * @param context Context aplikasi
         * @param delayMinutes Delay dalam menit sebelum worker dijalankan
         */
        fun scheduleRestart(context: Context, delayMinutes: Long = 15) {
            val workRequest = OneTimeWorkRequestBuilder<RestartWorker>()
                .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context).enqueue(workRequest)
        }
    }
}
