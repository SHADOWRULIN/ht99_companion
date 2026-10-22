package com.example.ht99_companion

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Vibrator
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.mediatek.wearable.LoadJniFunction
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.Calendar
import java.util.Date
import java.util.TimeZone
import java.util.UUID
import android.os.ParcelUuid

class MainActivity : FlutterActivity() {
    private val channelCts = "com.ht99.companion/cts"
    private val channelPhone = "com.ht99.companion/phone"
    private val channelMtk = "com.ht99.companion/mtk"

    private var gattServer: BluetoothGattServer? = null
    private var advertiserCallback: AdvertiseCallback? = null
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var nativeReady = false
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var servicesRegistered = 0
    private var advertisingStarted = false
    private var is24HourMode: Byte = 0
    private val connectedServerDevices = linkedSetOf<BluetoothDevice>()
    private val timeNotifyingDevices = linkedSetOf<BluetoothDevice>()
    private val formatNotifyingDevices = linkedSetOf<BluetoothDevice>()

    private val ctsServiceUuid = UUID.fromString("00001805-0000-1000-8000-00805f9b34fb")
    private val charCurrentTime = UUID.fromString("00002a2b-0000-1000-8000-00805f9b34fb")
    private val charLocalTime = UUID.fromString("00002a0f-0000-1000-8000-00805f9b34fb")
    private val charReferenceTime = UUID.fromString("00002a14-0000-1000-8000-00805f9b34fb")
    private val timeFormatServiceUuid = UUID.fromString("00001902-0000-1000-8000-00805f9b34fb")
    private val charTimeFormat = UUID.fromString("00002b01-0000-1000-8000-00805f9b34fb")
    private val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private val gattCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedServerDevices.add(device)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedServerDevices.remove(device)
                timeNotifyingDevices.remove(device)
                formatNotifyingDevices.remove(device)
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            val bytes = when (characteristic.uuid) {
                charCurrentTime -> getCurrentTimeBytes()
                charLocalTime -> getLocalTimeBytes()
                charReferenceTime -> byteArrayOf(1, 0xff.toByte(), 0, 0)
                charTimeFormat -> byteArrayOf(is24HourMode)
                else -> null
            }
            if (bytes == null || offset > bytes.size) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
            } else {
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    bytes.copyOfRange(offset, bytes.size)
                )
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            val isEnable = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ||
                value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)
            val isDisable = value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)
            if (descriptor.uuid == cccdUuid && (isEnable || isDisable)) {
                when (descriptor.characteristic?.uuid) {
                    charCurrentTime -> if (isEnable) timeNotifyingDevices.add(device) else timeNotifyingDevices.remove(device)
                    charTimeFormat -> if (isEnable) formatNotifyingDevices.add(device) else formatNotifyingDevices.remove(device)
                }
                descriptor.value = value
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
            } else if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, offset, null)
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            super.onServiceAdded(status, service)
            if (status != BluetoothGatt.GATT_SUCCESS) return
            servicesRegistered += 1
            if (servicesRegistered >= 2) startAdvertisingPhoneServices()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelCts).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCtsServer" -> {
                    if (needsServerPermission()) {
                        pendingPermissionResult = result
                        requestServerPermissions()
                    } else {
                        result.success(startCtsGattServer())
                    }
                }
                "broadcastCtsTime" -> result.success(notifyCurrentTime())
                "setTimeFormat" -> {
                    val is12Hour = call.argument<Boolean>("is12Hour") ?: true
                    is24HourMode = if (is12Hour) 0 else 1
                    updateTimeFormatCharacteristic()
                    result.success(notifyTimeFormat())
                }
                "stopCtsServer" -> {
                    stopCtsGattServer()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelPhone).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarm" -> { startPhoneAlarm(); result.success(true) }
                "stopAlarm" -> { stopPhoneAlarm(); result.success(true) }
                "openNotificationSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "isNotificationListenerEnabled" -> {
                    val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    result.success(enabled != null && enabled.contains(packageName))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelMtk).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    try {
                        // Confirmed in WWfit's Application startup: this exact key is passed to JNI.
                        LoadJniFunction.initialize("we had")
                        nativeReady = true
                        result.success(true)
                    } catch (t: Throwable) {
                        nativeReady = false
                        result.error("MTK_NATIVE_UNAVAILABLE", t.message ?: "Could not load MediaTek Command library", null)
                    }
                }
                "encodeCommand" -> {
                    try {
                        ensureNativeReady()
                        val type = call.argument<Int>("type") ?: throw IllegalArgumentException("Missing command type")
                        val body = call.argument<String>("body") ?: throw IllegalArgumentException("Missing command body")
                        val bytes = LoadJniFunction.encode(type, body)
                            ?: throw IllegalStateException("Native encoder returned no bytes")
                        result.success(bytes.map { it.toInt() and 0xff })
                    } catch (t: Throwable) {
                        result.error("MTK_ENCODE_FAILED", t.message ?: "Native encoding failed", null)
                    }
                }
                "inspectCommand" -> {
                    try {
                        ensureNativeReady()
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        val type = LoadJniFunction.inspectType(bytes, bytes.size)
                        val dataLength = LoadJniFunction.inspectDataLength(bytes, bytes.size)
                        result.success(mapOf(
                            "type" to type,
                            "dataLength" to dataLength,
                            "text" to String(bytes, Charsets.UTF_8).replace("\u0000", "").trim()
                        ))
                    } catch (t: Throwable) {
                        result.success(mapOf("type" to -1, "dataLength" to 0, "text" to ""))
                    }
                }
                "validateDialMd5" -> {
                    try {
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        result.success(validateDialMd5(bytes))
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        Ht99NotificationListener.flutterChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ht99.companion/notifications"
        )
    }

    private fun ensureNativeReady() {
        if (!nativeReady) {
            LoadJniFunction.initialize("we had")
            nativeReady = true
        }
    }

    private fun validateDialMd5(bytes: ByteArray): Boolean {
        if (bytes.size <= 32) return false
        val expected = String(bytes, 0, 32, Charsets.US_ASCII).uppercase()
        if (!expected.matches(Regex("[0-9A-F]{32}"))) return false
        val digest = MessageDigest.getInstance("MD5").digest(bytes.copyOfRange(32, bytes.size))
        val actual = digest.joinToString("") { "%02X".format(it.toInt() and 0xff) }
        return actual == expected
    }

    private fun startPhoneAlarm() {
        try {
            if (ringtone == null) {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ringtone = RingtoneManager.getRingtone(applicationContext, uri)
                ringtone?.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            }
            ringtone?.play()
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(android.os.VibrationEffect.createWaveform(longArrayOf(0, 700, 350, 700), 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 700, 350, 700), 0)
            }
        } catch (_: Exception) { }
    }

    private fun stopPhoneAlarm() {
        try { ringtone?.stop() } catch (_: Exception) { }
        try { vibrator?.cancel() } catch (_: Exception) { }
    }

    private fun needsServerPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED
    }

    private fun requestServerPermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            pendingPermissionResult?.success(startCtsGattServer())
            pendingPermissionResult = null
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE),
            REQUEST_SERVER_PERMISSIONS
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SERVER_PERMISSIONS) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            val result = pendingPermissionResult
            pendingPermissionResult = null
            result?.success(granted && startCtsGattServer())
        }
    }

    @SuppressLint("MissingPermission")
    private fun startCtsGattServer(): Boolean {
        if (needsServerPermission()) return false
        if (gattServer != null) return true
        return try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            if (adapter == null || !adapter.isEnabled) return false
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            gattServer = manager.openGattServer(this, gattCallback) ?: return false
            servicesRegistered = 0
            connectedServerDevices.clear()
            timeNotifyingDevices.clear()
            formatNotifyingDevices.clear()

            val cts = BluetoothGattService(ctsServiceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val current = BluetoothGattCharacteristic(
                charCurrentTime,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )
            current.value = getCurrentTimeBytes()
            current.addDescriptor(BluetoothGattDescriptor(cccdUuid, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
            cts.addCharacteristic(current)
            cts.addCharacteristic(BluetoothGattCharacteristic(
                charLocalTime,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ
            ))
            cts.addCharacteristic(BluetoothGattCharacteristic(
                charReferenceTime,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ
            ))

            val format = BluetoothGattService(timeFormatServiceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val formatChar = BluetoothGattCharacteristic(
                charTimeFormat,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )
            formatChar.value = byteArrayOf(is24HourMode)
            formatChar.addDescriptor(BluetoothGattDescriptor(cccdUuid, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
            format.addCharacteristic(formatChar)

            val ctsAdded = gattServer?.addService(cts) ?: false
            val formatAdded = gattServer?.addService(format) ?: false
            if (!ctsAdded || !formatAdded) {
                stopCtsGattServer()
                false
            } else true
        } catch (_: Throwable) {
            stopCtsGattServer()
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertisingPhoneServices() {
        if (advertisingStarted || Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) return
        try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter ?: return
            val advertiser = adapter.bluetoothLeAdvertiser ?: return
            val callback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    advertisingStarted = true
                }
                override fun onStartFailure(errorCode: Int) {
                    advertisingStarted = false
                }
            }
            advertiserCallback = callback
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(true)
                .setTimeout(0)
                .build()
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(ctsServiceUuid))
                .build()
            val scanResponse = AdvertiseData.Builder()
                .addServiceUuid(ParcelUuid(timeFormatServiceUuid))
                .build()
            advertiser.startAdvertising(settings, data, scanResponse, callback)
        } catch (_: Throwable) {
            advertisingStarted = false
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopCtsGattServer() {
        try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            val callback = advertiserCallback
            if (callback != null) adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
        } catch (_: Exception) { }
        advertiserCallback = null
        advertisingStarted = false
        servicesRegistered = 0
        try { gattServer?.clearServices() } catch (_: Exception) { }
        try { gattServer?.close() } catch (_: Exception) { }
        gattServer = null
        connectedServerDevices.clear()
        timeNotifyingDevices.clear()
        formatNotifyingDevices.clear()
    }

    private fun getCurrentTimeBytes(): ByteArray {
        val calendar = Calendar.getInstance()
        val year = calendar.get(Calendar.YEAR)
        // Bluetooth Current Time Service uses Monday=1 ... Sunday=7.
        val dayOfWeek = when (calendar.get(Calendar.DAY_OF_WEEK)) {
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
            (year and 0xff).toByte(), ((year shr 8) and 0xff).toByte(),
            (calendar.get(Calendar.MONTH) + 1).toByte(),
            calendar.get(Calendar.DAY_OF_MONTH).toByte(),
            calendar.get(Calendar.HOUR_OF_DAY).toByte(),
            calendar.get(Calendar.MINUTE).toByte(),
            calendar.get(Calendar.SECOND).toByte(),
            dayOfWeek.toByte(),
            ((calendar.get(Calendar.MILLISECOND) * 256) / 1000).toByte(),
            0.toByte()
        )
    }

    private fun getLocalTimeBytes(): ByteArray {
        val zone = TimeZone.getDefault()
        val now = Date()
        val currentOffset = zone.rawOffset + if (zone.inDaylightTime(now)) zone.dstSavings else 0
        val offsetQuarterHours = (currentOffset / (15 * 60 * 1000)).toByte()
        val dst = if (zone.inDaylightTime(now)) 2.toByte() else 0.toByte()
        return byteArrayOf(offsetQuarterHours, dst)
    }

    @SuppressLint("MissingPermission")
    private fun notifyCurrentTime(): Boolean {
        return try {
            val characteristic = gattServer?.getService(ctsServiceUuid)?.getCharacteristic(charCurrentTime) ?: return false
            characteristic.value = getCurrentTimeBytes()
            timeNotifyingDevices.toList().forEach { device ->
                gattServer?.notifyCharacteristicChanged(device, characteristic, false)
            }
            true
        } catch (_: Exception) { false }
    }

    @SuppressLint("MissingPermission")
    private fun updateTimeFormatCharacteristic() {
        try {
            val characteristic = gattServer?.getService(timeFormatServiceUuid)?.getCharacteristic(charTimeFormat)
            characteristic?.value = byteArrayOf(is24HourMode)
        } catch (_: Exception) { }
    }

    @SuppressLint("MissingPermission")
    private fun notifyTimeFormat(): Boolean {
        return try {
            updateTimeFormatCharacteristic()
            val characteristic = gattServer?.getService(timeFormatServiceUuid)?.getCharacteristic(charTimeFormat) ?: return false
            formatNotifyingDevices.toList().forEach { device ->
                gattServer?.notifyCharacteristicChanged(device, characteristic, false)
            }
            true
        } catch (_: Exception) { false }
    }

    override fun onDestroy() {
        stopPhoneAlarm()
        stopCtsGattServer()
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_SERVER_PERMISSIONS = 1002
    }
}
