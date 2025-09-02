package com.example.myxcreate  // <-- GANTI sesuai package kamu

import android.content.Context
import android.content.Intent
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

class RestartWorker(appContext: Context, workerParams: WorkerParameters) : Worker(appContext, workerParams) {

    override fun doWork(): Result {
        val ctx = applicationContext
        val i = Intent(ctx, ForegroundService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            ctx.startForegroundService(i)
        } else {
            ctx.startService(i)
        }
        return Result.success()
    }

    companion object {
        fun scheduleRestart(context: Context, delayMinutes: Long = 15) {
            val work = OneTimeWorkRequestBuilder<RestartWorker>()
                .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueue(work)
        }
    }
}
