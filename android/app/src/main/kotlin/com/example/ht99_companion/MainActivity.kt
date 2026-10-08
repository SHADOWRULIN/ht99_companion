package com.example.ht99_companion

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.ht99.companion/cts"
    private var gattServer: BluetoothGattServer? = null

    // Bluetooth SIG CTS (0x1805)
    private val CTS_SERVICE = UUID.fromString("00001805-0000-1000-8000-00805f9b34fb")
    private val CHAR_CURRENT_TIME = UUID.fromString("00002a2b-0000-1000-8000-00805f9b34fb")
    private val CHAR_LOCAL_TIME = UUID.fromString("00002a0f-0000-1000-8000-00805f9b34fb")
    private val CHAR_REF_TIME = UUID.fromString("00002a14-0000-1000-8000-00805f9b34fb")
    private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    // MediaTek Time Format Service (0x1902) from leprofiles.c & timeformat.b
    private val TIME_FORMAT_SERVICE = UUID.fromString("00001902-0000-1000-8000-00805f9b34fb")
    private val CHAR_TIME_FORMAT = UUID.fromString("00002b01-0000-1000-8000-00805f9b34fb")

    // 0 = 12-Hour format, 1 = 24-Hour format
    private var is24HourMode: Byte = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCtsServer" -> {
                    val ok = startCtsGattServer()
                    result.success(ok)
                }
                "broadcastCtsTime" -> {
                    notifyCurrentTime()
                    result.success(true)
                }
                "setTimeFormat" -> {
                    val is12Hour = call.argument<Boolean>("is12Hour") ?: true
                    is24HourMode = if (is12Hour) 0 else 1
                    notifyTimeFormat()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startCtsGattServer(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }
        if (gattServer != null) return true

        return try {
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

            // 1. Register Current Time Service (0x1805)
            val ctsService = BluetoothGattService(CTS_SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)

            val timeChar = BluetoothGattCharacteristic(
                CHAR_CURRENT_TIME,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )
            timeChar.addDescriptor(BluetoothGattDescriptor(CCCD_UUID, BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ))

            val localChar = BluetoothGattCharacteristic(
                CHAR_LOCAL_TIME,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ
            )

            val refChar = BluetoothGattCharacteristic(
                CHAR_REF_TIME,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ
            )

            ctsService.addCharacteristic(timeChar)
            ctsService.addCharacteristic(localChar)
            ctsService.addCharacteristic(refChar)
            gattServer?.addService(ctsService)

            // 2. Register MediaTek Time Format Service (0x1902)
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

            true
        } catch (_: Exception) {
            false
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
        try { gattServer?.close() } catch (_: Exception) {}
    }
}