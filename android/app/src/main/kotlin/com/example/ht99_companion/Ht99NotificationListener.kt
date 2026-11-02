package com.example.ht99_companion

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.MethodChannel

class Ht99NotificationListener : NotificationListenerService() {
    companion object {
        var flutterChannel: MethodChannel? = null
        @Volatile
        var allowed: Set<String> = emptySet()
        @Volatile
        var filterActive: Boolean = false
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        if (filterActive && !allowed.contains(pkg)) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString()?.trim() ?: ""
        val text = extras.getCharSequence("android.text")?.toString()?.trim() ?: ""

        if (title.isEmpty() && text.isEmpty()) return

        val isCall = pkg.contains("telecom") || pkg.contains("dialer") || pkg.contains("incallui")
        WatchEngine.pushNotification(pkg, title, text, isCall)

        val payload = mapOf(
            "package" to pkg,
            "title" to title,
            "body" to text
        )
        try {
            flutterChannel?.invokeMethod("onNotificationReceived", payload)
        } catch (_: Exception) {}
    }
}