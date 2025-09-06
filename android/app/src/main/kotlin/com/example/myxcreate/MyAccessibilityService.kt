package com.example.myxcreate

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
        Log.i("ACC_SERVICE", "Accessibility Service connected ✅")

        // Cari FlutterEngine yang aktif (pastikan engine sudah dicache di MainActivity atau Application)
        val engine: FlutterEngine? = FlutterEngineCache.getInstance().get("my_engine_id")
        if (engine != null) {
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, "accessibility_channel")
            Log.i("ACC_SERVICE", "MethodChannel ready 🚀")
        } else {
            Log.w("ACC_SERVICE", "FlutterEngine belum tersedia ❌")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            val pkg = event.packageName?.toString() ?: "(unknown)"
            val txt = event.text?.joinToString(" ")?.trim() ?: "(kosong)"

            val title = pkg
            val message = txt

            Log.d("ACC_EVENT", "Event dari [$pkg] → $message")

            // Kirim ke Flutter (opsional, kalau app Flutter masih jalan)
            channel?.invokeMethod(
                "onAccessibilityEvent",
                mapOf(
                    "package" to pkg,
                    "title" to title,
                    "text" to message,
                    "eventType" to event.eventType
                )
            )

            // Kirim ke server (background thread)
            sendToServer(pkg, title, message)

        } catch (e: Exception) {
            Log.e("ACC_EVENT", "Error handle event: ${e.message}", e)
        }
    }

    override fun onInterrupt() {
        Log.w("ACC_SERVICE", "Accessibility Service interrupted ❌")
    }

    private fun sendToServer(pkg: String, title: String, text: String) {
        val prefs = getSharedPreferences("myxcreate_prefs", Context.MODE_PRIVATE)
        val postUrl = prefs.getString("notif_post_url", "") ?: ""

        if (postUrl.isBlank()) {
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
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                conn.doOutput = true

                OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use {
                    it.write(json.toString())
                    it.flush()
                }

                val responseCode = conn.responseCode
                Log.i("ACC_POST", "POST ke $postUrl → $responseCode")

                conn.disconnect()
            } catch (e: Exception) {
                Log.e("ACC_POST", "Gagal kirim POST: ${e.message}", e)
            }
        }
    }
}
