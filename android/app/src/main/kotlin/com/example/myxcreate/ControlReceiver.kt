// android/app/src/main/kotlin/com/example/myxcreate/ControlReceiver.kt
package com.example.myxcreate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == "com.example.myxcreate.ACTION_STOP_SERVICE") {
            // stop service
            val svc = Intent(context, ForegroundStarterService::class.java)
            context.stopService(svc)
            // clear enabled flag in prefs
            val sp = context.getSharedPreferences("myxcreate_prefs", Context.MODE_PRIVATE)
            sp.edit().putBoolean("enabled", false).apply()
        }
    }
}
