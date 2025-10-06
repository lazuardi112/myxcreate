package com.example.myxcreate

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.os.Build
import android.content.Context
import okhttp3.*
import java.io.IOException
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

class MyNotificationListenerService : NotificationListenerService() {
    private val TAG = "MyNotifListener"
    private val gson = Gson()
    private val client = OkHttpClient()

    companion object {
        const val PREFS_FILE = "FlutterSharedPreferences" // Flutter's prefs file
        const val KEY_ENABLED = "xc_listener_enabled"
        const val KEY_SELECTED = "xc_selected_apps"
        const val KEY_POSTURL = "xc_post_url"
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val prefs = applicationContext.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

            val enabled = prefs.getBoolean(KEY_ENABLED, false)
            if (!enabled) {
                Log.d(TAG, "Listener disabled in prefs, ignoring.")
                return
            }

            val packageName = sbn.packageName ?: return

            // Read selected apps JSON (stored by Flutter)
            val selRaw = prefs.getString(KEY_SELECTED, "[]") ?: "[]"
            val type = object : TypeToken<List<String>>() {}.type
            val selectedList: List<String> = try {
                gson.fromJson(selRaw, type)
            } catch (e: Exception) {
                Log.w(TAG, "Failed parse selected json: $e")
                emptyList()
            }

            // If list not empty, filter
            if (selectedList.isNotEmpty() && !selectedList.contains(packageName)) {
                Log.d(TAG, "Package $packageName not selected, skip")
                return
            }

            // fetch post url
            val postUrl = prefs.getString(KEY_POSTURL, "") ?: ""
            // build title/text from extras
            val extras = sbn.notification?.extras
            val title = extras?.getString("android.title") ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""

            Log.d(TAG, "Captured notif from $packageName title=$title text=$text url=$postUrl")

            // send POST if url configured
            if (postUrl.isNotEmpty()) {
                postToServer(postUrl, packageName, title, text)
            }

        } catch (e: Exception) {
            Log.e(TAG, "onNotificationPosted error: $e")
        }
    }

    private fun postToServer(url: String, app: String, title: String, text: String) {
        val form = FormBody.Builder()
            .add("app", app)
            .add("title", title)
            .add("text", text)
            .build()

        val req = Request.Builder()
            .url(url)
            .post(form)
            .build()

        client.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "POST failed: ${e.message}")
            }

            override fun onResponse(call: Call, response: Response) {
                Log.d(TAG, "POST success code=${response.code}")
                response.close()
            }
        })
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "Listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "Listener disconnected")
    }
}
