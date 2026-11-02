package com.example.ht99_companion

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Vibrator
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL_ENGINE = "ht99/engine"
    private val CHANNEL_EVENTS = "ht99/events"
    private val CHANNEL_CTS = "com.ht99.companion/cts"
    private val CHANNEL_PHONE = "com.ht99.companion/phone"

    private var gattServer: BluetoothGattServer? = null
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var pendingPermResult: MethodChannel.Result? = null

    private val CTS_SERVICE = UUID.fromString("00001805-0000-1000-8000-00805f9b34fb")
    private val CHAR_CURRENT_TIME = UUID.fromString("00002a2b-0000-1000-8000-00805f9b34fb")
    private val CHAR_LOCAL_TIME = UUID.fromString("00002a0f-0000-1000-8000-00805f9b34fb")
    private val CHAR_REF_TIME = UUID.fromString("00002a14-0000-1000-8000-00805f9b34fb")
    private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private val TIME_FORMAT_SERVICE = UUID.fromString("00001902-0000-1000-8000-00805f9b34fb")
    private val CHAR_TIME_FORMAT = UUID.fromString("00002b01-0000-1000-8000-00805f9b34fb")
    private var is24HourMode: Byte = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        WatchEngine.init(applicationContext)
        WatchEngine.onStartPhoneAlarm = { startPhoneAlarm() }
        WatchEngine.onStopPhoneAlarm = { stopPhoneAlarm() }
        WatchEngine.onCtsSyncRequested = { is12Hour ->
            is24HourMode = if (is12Hour) 0 else 1
            startCtsGattServer()
            notifyCurrentTime()
            notifyTimeFormat()
        }

        // 1. Live Event Stream to Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    WatchEngine.sink = { map -> events?.success(map) }
                }

                override fun onCancel(args: Any?) {
                    WatchEngine.sink = null
                }
            }
        )

        // 2. Primary Native Watch Engine Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_ENGINE).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> requestBlePermissions(result)
                "scanAndConnect" -> {
                    startCtsGattServer()
                    WatchEngine.scanAndConnect()
                    result.success(true)
                }
                "stopScan" -> {
                    WatchEngine.stopScan()
                    result.success(true)
                }
                "disconnect" -> {
                    val forget = call.argument<Boolean>("forget") ?: false
                    WatchEngine.disconnect(forget)
                    result.success(true)
                }
                "state" -> result.success(WatchEngine.currentState())
                "ww" -> {
                    val cmd = call.argument<String>("cmd") ?: ""
                    result.success(WatchEngine.sendWw(cmd))
                }
                "pedometer" -> {
                    val cmd = call.argument<String>("cmd") ?: "GET,0"
                    result.success(WatchEngine.sendPedometer(cmd))
                }
                "raw" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    result.success(WatchEngine.write(bytes))
                }
                "syncTime" -> {
                    val use24 = call.argument<Boolean>("is24Hour")
                    result.success(WatchEngine.syncTime(use24))
                }
                "readBattery" -> {
                    WatchEngine.readBattery()
                    result.success(true)
                }
                "immediateAlert" -> {
                    val level = call.argument<Int>("level") ?: 2
                    WatchEngine.immediateAlert(level)
                    result.success(true)
                }
                "notify" -> {
                    val pkg = call.argument<String>("pkg") ?: "com.whatsapp"
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val isCall = call.argument<Boolean>("isCall") ?: false
                    result.success(WatchEngine.pushNotification(pkg, title, body, isCall))
                }
                "weather" -> {
                    val city = call.argument<String>("city") ?: "Local"
                    val cond = call.argument<Int>("conditionCode") ?: 0
                    val temp = call.argument<Int>("tempC") ?: 25
                    val high = call.argument<Int>("highC") ?: 30
                    val low = call.argument<Int>("lowC") ?: 20
                    result.success(WatchEngine.pushWeather(city, cond, temp, high, low))
                }
                "setAllowedPackages" -> {
                    val pkgs = call.argument<List<String>>("pkgs") ?: emptyList()
                    Ht99NotificationListener.allowed = pkgs.toSet()
                    Ht99NotificationListener.filterActive = true
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 3. CTS & TimeFormat Local GATT Server Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CTS).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCtsServer" -> result.success(startCtsGattServer())
                "broadcastCtsTime" -> {
                    notifyCurrentTime()
                    result.success(true)
                }
                "setTimeFormat" -> {
                    val is12Hour = call.argument<Boolean>("is12Hour") ?: true
                    is24HourMode = if (is12Hour) 0 else 1
                    notifyTimeFormat()
                    WatchEngine.syncTime(!is12Hour)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 4. Phone Ringtone & Notification Settings Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PHONE).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarm" -> {
                    startPhoneAlarm()
                    result.success(true)
                }
                "stopAlarm" -> {
                    stopPhoneAlarm()
                    WatchEngine.sendWw("10,4,0")
                    result.success(true)
                }
                "openNotificationSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "isNotificationListenerEnabled" -> {
                    val pkgName = packageName
                    val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    result.success(flat != null && flat.contains(pkgName))
                }
                else -> result.notImplemented()
            }
        }

        Ht99NotificationListener.flutterChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ht99.companion/notifications"
        )
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.BLUETOOTH_SCAN)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        if (needed.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermResult = result
        ActivityCompat.requestPermissions(this, needed.toTypedArray(), 9901)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9901) {
            val res = pendingPermResult
            pendingPermResult = null
            res?.success(grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        }
    }

    private fun startPhoneAlarm() {
        try {
            if (ringtone == null) {
                val alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ringtone = RingtoneManager.getRingtone(applicationContext, alertUri)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    ringtone?.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                }
            }
            ringtone?.play()

            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            val pattern = longArrayOf(0, 800, 400, 800)
            vibrator?.vibrate(pattern, 0)
        } catch (_: Exception) {}
    }

    private fun stopPhoneAlarm() {
        try {
            ringtone?.stop()
            vibrator?.cancel()
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    private fun startCtsGattServer(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }
        if (gattServer != null) return true

        try {
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return false
            gattServer = bm.openGattServer(this, object : BluetoothGattServerCallback() {
                override fun onCharacteristicReadRequest(
                    device: BluetoothDevice?,
                    requestId: Int,
                    offset: Int,
                    characteristic: BluetoothGattCharacteristic?
                ) {
                    super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
                    when (characteristic?.uuid) {
                        CHAR_CURRENT_TIME -> gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, getCurrentTimeBytes())
                        CHAR_LOCAL_TIME -> gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, getLocalTimeBytes())
                        CHAR_REF_TIME -> gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, byteArrayOf(1, 255.toByte(), 0, 0))
                        CHAR_TIME_FORMAT -> gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, byteArrayOf(is24HourMode))
                        else -> gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
                    }
                }

                override fun onDescriptorWriteRequest(
                    device: BluetoothDevice?,
                    requestId: Int,
                    descriptor: BluetoothGattDescriptor?,
                    preparedWrite: Boolean,
                    responseNeeded: Boolean,
                    offset: Int,
                    value: ByteArray?
                ) {
                    super.onDescriptorWriteRequest(device, requestId, descriptor, preparedWrite, responseNeeded, offset, value)
                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                    }
                }
            })

            val ctsService = BluetoothGattService(CTS_SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val timeChar = BluetoothGattCharacteristic(
                CHAR_CURRENT_TIME,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )
            timeChar.addDescriptor(BluetoothGattDescriptor(CCCD_UUID, BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ))
            val localChar = BluetoothGattCharacteristic(CHAR_LOCAL_TIME, BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ)
            val refChar = BluetoothGattCharacteristic(CHAR_REF_TIME, BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ)

            ctsService.addCharacteristic(timeChar)
            ctsService.addCharacteristic(localChar)
            ctsService.addCharacteristic(refChar)
            gattServer?.addService(ctsService)

            val tfService = BluetoothGattService(TIME_FORMAT_SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val tfChar = BluetoothGattCharacteristic(
                CHAR_TIME_FORMAT,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )
            tfChar.addDescriptor(BluetoothGattDescriptor(CCCD_UUID, BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ))
            tfChar.value = byteArrayOf(is24HourMode)
            tfService.addCharacteristic(tfChar)
            gattServer?.addService(tfService)

            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun getCurrentTimeBytes(): ByteArray {
        val cal = Calendar.getInstance()
        val year = cal.get(Calendar.YEAR)
        val dayOfWeek = when (cal.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> 1
            Calendar.TUESDAY -> 2
            Calendar.WEDNESDAY -> 3
            Calendar.THURSDAY -> 4
            Calendar.FRIDAY -> 5
            Calendar.SATURDAY -> 6
            Calendar.SUNDAY -> 7
            else -> 0
        }
        return byteArrayOf(
            (year and 0xFF).toByte(),
            ((year shr 8) and 0xFF).toByte(),
            (cal.get(Calendar.MONTH) + 1).toByte(),
            cal.get(Calendar.DAY_OF_MONTH).toByte(),
            cal.get(Calendar.HOUR_OF_DAY).toByte(),
            cal.get(Calendar.MINUTE).toByte(),
            cal.get(Calendar.SECOND).toByte(),
            dayOfWeek.toByte(),
            ((cal.get(Calendar.MILLISECOND) * 256) / 1000).toByte(),
            0.toByte()
        )
    }

    private fun getLocalTimeBytes(): ByteArray {
        val tz = TimeZone.getDefault()
        val rawOffsetHours = (tz.rawOffset / (1000 * 60 * 60) * 4).toByte()
        val dst = if (tz.inDaylightTime(Date())) 4.toByte() else 0.toByte()
        return byteArrayOf(rawOffsetHours, dst)
    }

    @SuppressLint("MissingPermission")
    private fun notifyCurrentTime() {
        try {
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return
            val devices = bm.getConnectedDevices(BluetoothProfile.GATT)
            val service = gattServer?.getService(CTS_SERVICE)
            val char = service?.getCharacteristic(CHAR_CURRENT_TIME) ?: return
            char.value = getCurrentTimeBytes()
            for (d in devices) {
                gattServer?.notifyCharacteristicChanged(d, char, false)
            }
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    private fun notifyTimeFormat() {
        try {
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return
            val devices = bm.getConnectedDevices(BluetoothProfile.GATT)
            val service = gattServer?.getService(TIME_FORMAT_SERVICE)
            val char = service?.getCharacteristic(CHAR_TIME_FORMAT) ?: return
            char.value = byteArrayOf(is24HourMode)
            for (d in devices) {
                gattServer?.notifyCharacteristicChanged(d, char, false)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        stopPhoneAlarm()
        try {
            gattServer?.close()
        } catch (_: Exception) {}
    }
}