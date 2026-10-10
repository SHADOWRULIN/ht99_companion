package com.example.ht99_companion

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.MethodChannel

class Ht99NotificationListener : NotificationListenerService() {
    companion object {
        var flutterChannel: MethodChannel? = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val pkg = sbn.packageName ?: ""

        if (title.isNotEmpty() || text.isNotEmpty()) {
            val payload = mapOf(
                "package" to pkg,
                "title" to title,
                "body" to text
            )
            flutterChannel?.invokeMethod("onNotificationReceived", payload)
        }
    }
}