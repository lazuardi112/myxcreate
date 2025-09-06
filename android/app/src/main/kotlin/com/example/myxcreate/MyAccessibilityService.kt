package com.yourpackage

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class MyAccessibilityService : AccessibilityService() {

    private var channel: MethodChannel? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("ACC_SERVICE", "Accessibility Service connected ✅")

        // Cari FlutterEngine yang aktif
        val engine: FlutterEngine? = FlutterEngineCache.getInstance().get("my_engine_id")
        engine?.let {
            channel = MethodChannel(it.dartExecutor.binaryMessenger, "accessibility_channel")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            val pkg = event.packageName?.toString() ?: "(unknown)"
            val txt = event.text?.joinToString(" ") ?: "(kosong)"

            // Anggap title = nama package, isi = text
            val title = pkg
            val message = txt

            Log.d("ACC_EVENT", "[$pkg] $message")

            // Kirim ke Flutter (opsional, kalau masih dipakai)
            channel?.invokeMethod("onAccessibilityEvent", mapOf(
                "package" to pkg,
                "title" to title,
                "text" to message,
                "eventType" to event.eventType
            ))

            // 🔥 Kirim ke server langsung
            sendToServer(pkg, title, message)

        } catch (e: Exception) {
            Log.e("ACC_EVENT", "Error handle event: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.w("ACC_SERVICE", "Service interrupted ❌")
    }

    private fun sendToServer(pkg: String, title: String, text: String) {
        // Ambil URL dari SharedPreferences
        val prefs = getSharedPreferences("myxcreate_prefs", Context.MODE_PRIVATE)
        val postUrl = prefs.getString("notif_post_url", "") ?: ""

        if (postUrl.isEmpty()) {
            Log.w("ACC_POST", "notif_post_url belum di-set ❌")
            return
        }

        thread {
            try {
                val json = JSONObject().apply {
                    put("package", pkg)
                    put("title", title)
                    put("text", text)
                    put("timestamp", System.currentTimeMillis())
                }

                val url = URL(postUrl)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                conn.doOutput = true

                OutputStreamWriter(conn.outputStream).use { it.write(json.toString()) }

                val responseCode = conn.responseCode
                Log.d("ACC_POST", "POST ke $postUrl => $responseCode")

                conn.disconnect()
            } catch (e: Exception) {
                Log.e("ACC_POST", "Gagal kirim POST: ${e.message}")
            }
        }
    }
}
