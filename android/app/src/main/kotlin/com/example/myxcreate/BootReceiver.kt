// android/app/src/main/kotlin/com/example/myxcreate/BootReceiver.kt
package com.example.myxcreate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            val sp = context.getSharedPreferences("myxcreate_prefs", Context.MODE_PRIVATE)
            val enabled = sp.getBoolean("enabled", false)
            if (enabled) {
                val i = Intent(context, ForegroundStarterService::class.java)
                ContextCompat.startForegroundService(context, i)
            }
        }
    }
}
