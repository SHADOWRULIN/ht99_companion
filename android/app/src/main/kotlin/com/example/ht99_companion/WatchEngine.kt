package com.example.ht99_companion

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.*

/**
 * Native 64-bit BLE engine for the HT99 (MTK2502 / KCT) smartwatch.
 * Serializes all GATT operations on the main looper and performs the
 * authentic MediaTek RC4 handshake and WWfit telemetry polling.
 */
@SuppressLint("MissingPermission")
object WatchEngine {
    // MediaTek DOGP Service & Characteristics
    val SVC_DATA: UUID = UUID.fromString("000018a0-0000-1000-8000-00805f9b34fb")
    val CH_WRITE: UUID = UUID.fromString("00002aa1-0000-1000-8000-00805f9b34fb")
    val CH_NOTIFY: UUID = UUID.fromString("00002aa0-0000-1000-8000-00805f9b34fb")
    val CH_DOGP_IND: UUID = UUID.fromString("00002abc-0000-1000-8000-00805f9b34fb")

    // Standard SIG & MediaTek Profile UUIDs
    val SVC_BATT: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
    val CH_BATT: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
    val SVC_IMM: UUID = UUID.fromString("00001802-0000-1000-8000-00805f9b34fb")
    val CH_ALERT: UUID = UUID.fromString("00002a06-0000-1000-8000-00805f9b34fb")
    val SVC_PDMS: UUID = UUID.fromString("000018aa-0000-1000-8000-00805f9b34fb")
    val CH_PDMS: UUID = UUID.fromString("00002aaa-0000-1000-8000-00805f9b34fb")
    val SVC_HR: UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
    val CH_HR: UUID = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    // Fallback KCT UUIDs (s1.g)
    val KCT_WRITE_1: UUID = UUID.fromString("c3e6fea1-e966-1000-8000-be99c223df6a")
    val KCT_NOTIFY_1: UUID = UUID.fromString("c3e6fea2-e966-1000-8000-be99c223df6a")
    val KCT_WRITE_2: UUID = UUID.fromString("0783b03e-8535-b5a0-7140-a304d2495cba")
    val KCT_NOTIFY_2: UUID = UUID.fromString("0783b03e-8535-b5a0-7140-a304d2495cb8")

    private val main = Handler(Looper.getMainLooper())
    private lateinit var app: Context
    private val prefs get() = app.getSharedPreferences("ht99_prefs", Context.MODE_PRIVATE)

    var sink: ((Map<String, Any?>) -> Unit)? = null
    var onStartPhoneAlarm: (() -> Unit)? = null
    var onStopPhoneAlarm: (() -> Unit)? = null
    var onCtsSyncRequested: ((Boolean) -> Unit)? = null

    private var gatt: BluetoothGatt? = null
    private var writeChar: BluetoothGattCharacteristic? = null
    private var alertChar: BluetoothGattCharacteristic? = null
    private var battChar: BluetoothGattCharacteristic? = null
    private var pdmsChar: BluetoothGattCharacteristic? = null

    private var isScanning = false
    var isConnecting = false
        private set
    var isConnected = false
        private set
    var is24Hour = false
    private var msgIdCounter = 1
    private var chunkSize = 20

    private val parser = MtkCodec.StreamParser()
    private val ops = java.util.ArrayDeque<() -> Unit>()
    private var opBusy = false

    private val opTimeoutRunnable = Runnable {
        if (opBusy) {
            opBusy = false
            nextOp()
        }
    }

    fun init(context: Context) {
        app = context.applicationContext
        is24Hour = prefs.getBoolean("is24Hour", false)
    }

    private fun emit(event: Map<String, Any?>) {
        main.post {
            try {
                sink?.invoke(event)
            } catch (_: Exception) {}
        }
    }

    fun log(msg: String) {
        emit(mapOf("type" to "log", "message" to msg))
    }

    private fun emitState(statusText: String) {
        emit(
            mapOf(
                "type" to "state",
                "connected" to isConnected,
                "connecting" to isConnecting,
                "status" to statusText
            )
        )
    }

    fun currentState(): Map<String, Any?> {
        return mapOf(
            "connected" to isConnected,
            "connecting" to isConnecting,
            "is24Hour" to is24Hour
        )
    }

    // ---- BLE Operation Queue ----

    private fun enqueueOp(block: () -> Unit) {
        main.post {
            ops.addLast(block)
            if (!opBusy) {
                nextOp()
            }
        }
    }

    private fun nextOp() {
        main.removeCallbacks(opTimeoutRunnable)
        val next = ops.pollFirst()
        if (next == null) {
            opBusy = false
            return
        }
        opBusy = true
        main.postDelayed(opTimeoutRunnable, 650L)
        try {
            next.invoke()
        } catch (e: Exception) {
            log("GATT op error: ${e.message}")
            opBusy = false
            nextOp()
        }
    }

    private fun completeOp() {
        main.post {
            main.removeCallbacks(opTimeoutRunnable)
            opBusy = false
            nextOp()
        }
    }

    // ---- Scanning & Connection ----

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            val device = result?.device ?: return
            val name = (device.name ?: result.scanRecord?.deviceName ?: "").uppercase(Locale.ROOT)
            val mac = device.address?.uppercase(Locale.ROOT) ?: ""
            val savedMac = prefs.getString("saved_mac", "") ?: ""

            if (name.contains("HT99") ||
                (savedMac.isNotEmpty() && mac == savedMac) ||
                mac.startsWith("FC:84") ||
                mac.startsWith("F9:47") ||
                mac.startsWith("D0:CC") ||
                mac.startsWith("F3:D7") ||
                mac.startsWith("CC:76")
            ) {
                log("Acquired target: ${name.ifEmpty { "HT99" }} [$mac]")
                prefs.edit().putString("saved_mac", mac).apply()
                stopScan()
                connectToDevice(device)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            log("BLE Scan failed with code: $errorCode")
            isScanning = false
            isConnecting = false
            emitState("Scan failed ($errorCode)")
        }
    }

    fun scanAndConnect() {
        if (isConnected || isConnecting) return
        val bm = app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = bm?.adapter
        if (adapter == null || !adapter.isEnabled) {
            log("Bluetooth is disabled")
            emitState("Bluetooth is off")
            return
        }

        isConnecting = true
        emitState("Scanning for HT99...")
        log("Scanning for HT99...")

        // 1. Check if watch is already connected at OS GATT level
        try {
            val connectedDevs = bm.getConnectedDevices(BluetoothProfile.GATT)
            for (d in connectedDevs) {
                val n = (d.name ?: "").uppercase(Locale.ROOT)
                val m = d.address.uppercase(Locale.ROOT)
                if (n.contains("HT99") || m.startsWith("FC:84") || m.startsWith("F9:47")) {
                    log("Found already-connected HT99 [$m]. Binding...")
                    connectToDevice(d)
                    return
                }
            }
        } catch (_: Exception) {}

        // 2. Start BLE Scan
        try {
            val scanner = adapter.bluetoothLeScanner
            if (scanner != null) {
                isScanning = true
                val settings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .build()
                scanner.startScan(null, settings, scanCallback)
                main.postDelayed({
                    if (isScanning) {
                        stopScan()
                        if (!isConnected) {
                            isConnecting = false
                            log("Scan timed out. Ensure watch is awake.")
                            emitState("Watch not found")
                        }
                    }
                }, 15000L)
            } else {
                isConnecting = false
                emitState("BLE Scanner unavailable")
            }
        } catch (e: Exception) {
            log("Scan exception: ${e.message}")
            isConnecting = false
            emitState("Scan error")
        }
    }

    fun stopScan() {
        if (!isScanning) return
        isScanning = false
        try {
            val bm = app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bm?.adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (_: Exception) {}
    }

    private fun connectToDevice(device: BluetoothDevice) {
        main.post {
            try {
                gatt?.close()
            } catch (_: Exception) {}
            gatt = null
            parser.reset()
            ops.clear()
            opBusy = false

            emitState("Found HT99. Binding...")
            log("Connecting GATT to ${device.address}...")
            gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(app, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(app, false, gattCallback)
            }
        }
    }

    fun disconnect(forget: Boolean = false) {
        stopScan()
        main.post {
            if (forget) {
                prefs.edit().remove("saved_mac").apply()
            }
            ops.clear()
            opBusy = false
            parser.reset()
            try {
                gatt?.disconnect()
                gatt?.close()
            } catch (_: Exception) {}
            gatt = null
            writeChar = null
            alertChar = null
            battChar = null
            pdmsChar = null
            isConnected = false
            isConnecting = false
            log("Watch disconnected")
            emitState("Disconnected")
        }
    }

    // ---- GATT Callback ----

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                main.post {
                    isConnected = true
                    isConnecting = false
                    parser.reset()
                    log("Connected. Requesting MTU & discovering services...")
                    emitState("Connected. Initializing...")

                    enqueueOp {
                        if (!g.requestMtu(256)) {
                            completeOp()
                        }
                    }
                    enqueueOp {
                        if (!g.discoverServices()) {
                            completeOp()
                        }
                    }
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                main.post {
                    val wasConnected = isConnected
                    isConnected = false
                    isConnecting = false
                    ops.clear()
                    opBusy = false
                    parser.reset()
                    try {
                        g.close()
                    } catch (_: Exception) {}
                    if (gatt == g) gatt = null
                    log("Watch link disconnected (status=$status)")
                    emitState("Disconnected")
                    if (wasConnected) {
                        onStopPhoneAlarm?.invoke()
                    }
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS && mtu > 23) {
                // Keep 20-byte chunking for MTK DOGP safety, as g0.java slices at 20 bytes
                chunkSize = 20
                log("MTU negotiated: $mtu")
            }
            completeOp()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            completeOp()
            if (status != BluetoothGatt.GATT_SUCCESS) {
                log("Service discovery failed: $status")
                return
            }

            main.post {
                bindCharacteristics(g)
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            completeOp()
        }

        override fun onCharacteristicRead(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val data = characteristic.value ?: ByteArray(0)
                handleIncomingBytes(characteristic.uuid, data)
            }
            completeOp()
        }

        override fun onCharacteristicWrite(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            completeOp()
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            val data = characteristic.value ?: return
            handleIncomingBytes(characteristic.uuid, data)
        }
    }

    private fun bindCharacteristics(g: BluetoothGatt) {
        writeChar = null
        alertChar = null
        battChar = null
        pdmsChar = null

        val notifyTargets = mutableListOf<BluetoothGattCharacteristic>()

        for (s in g.services) {
            for (c in s.characteristics) {
                val u = c.uuid
                when (u) {
                    CH_WRITE -> writeChar = c
                    KCT_WRITE_1, KCT_WRITE_2 -> if (writeChar == null) writeChar = c
                    CH_ALERT -> alertChar = c
                    CH_BATT -> battChar = c
                    CH_PDMS -> pdmsChar = c
                }
                if (u == CH_NOTIFY || u == CH_DOGP_IND || u == CH_PDMS || u == CH_HR || u == CH_BATT ||
                    u == KCT_NOTIFY_1 || u == KCT_NOTIFY_2
                ) {
                    notifyTargets.add(c)
                }
            }
        }

        // Fallback writable characteristic if 2AA1 was not matched
        if (writeChar == null) {
            for (s in g.services) {
                for (c in s.characteristics) {
                    if (c.uuid != CH_ALERT &&
                        ((c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0 ||
                         (c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0)
                    ) {
                        writeChar = c
                        break
                    }
                }
                if (writeChar != null) break
            }
        }

        log("Endpoints bound: Write=${writeChar?.uuid?.toString()?.take(8) ?: "none"}, Notifies=${notifyTargets.size}")

        // Enable notifications sequentially via the GATT queue
        for (nc in notifyTargets) {
            enqueueOp {
                try {
                    g.setCharacteristicNotification(nc, true)
                    val desc = nc.getDescriptor(CCCD)
                    if (desc != null) {
                        val useIndicate = (nc.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0 &&
                                (nc.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) == 0
                        desc.value = if (useIndicate) {
                            BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                        } else {
                            BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        }
                        if (!g.writeDescriptor(desc)) {
                            completeOp()
                        }
                    } else {
                        completeOp()
                    }
                } catch (_: Exception) {
                    completeOp()
                }
            }
        }

        // After all descriptors are enabled, run the authentic MediaTek + WWfit handshake
        enqueueOp {
            log("Notifications active. Running MTK + WWfit handshake...")
            emitState("Connected & Synchronized")
            completeOp()
            runPostConnectSequence()
        }
    }

    private fun runPostConnectSequence() {
        // 1. Read standard SIG battery (0x2A19) immediately
        readBattery()

        // 2. Broadcast phone CTS server time & time format
        onCtsSyncRequested?.invoke(!is24Hour)

        // 3. Send MTK SYNC time packet (Type 2) and bnsrv_time packet (Type 9)
        syncTime(is24Hour)

        // 4. Send language sync ("language mtk_language 1 0 5 en_US")
        val langBytes = "en_US".toByteArray(Charsets.UTF_8)
        write(MtkCodec.encodePacket(MtkCodec.T_EXCD, "language mtk_language 1 0 ${langBytes.size} ", langBytes))

        // 5. Activate PDMS step sensor (0x2AAA) if present on watch
        pdmsChar?.let { pc ->
            enqueueOp {
                pc.value = byteArrayOf(10, 0, 1, 0, 10, 0)
                pc.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                if (gatt?.writeCharacteristic(pc) != true) {
                    completeOp()
                }
            }
        }

        // 6. Staggered WWfit startup queries matching c.c()
        val startupCmds = listOf(
            if (is24Hour) "SET,40,1" else "SET,40,0",
            "PS,GET",
            "GET,10",
            "01,1",
            "11,1",
            "03,1",
            "04,1",
            "05,1",
            "13,1",
            "14,1",
            "15,1"
        )

        startupCmds.forEachIndexed { idx, cmd ->
            main.postDelayed({
                if (isConnected) {
                    sendWw(cmd)
                }
            }, (idx + 1) * 180L)
        }

        main.postDelayed({
            if (isConnected) {
                sendPedometer("GET,0")
            }
        }, (startupCmds.size + 1) * 180L)
    }

    // ---- Incoming Data Parser ----

    private fun handleIncomingBytes(uuid: UUID, data: ByteArray) {
        if (data.isEmpty()) return
        val shortUuid = uuid.toString().substring(4, 8).lowercase(Locale.ROOT)
        val hex = data.joinToString(" ") { "%02x".format(it) }

        // 1. Standard SIG Battery (0x2A19)
        if (uuid == CH_BATT) {
            val pct = (data[0].toInt() and 0xFF).coerceIn(0, 100)
            log("SIG Battery: $pct%")
            emit(mapOf("type" to "telemetry", "battery" to pct))
            return
        }

        // 2. Standard SIG Heart Rate (0x2A37)
        if (uuid == CH_HR && data.size >= 2) {
            val bpm = data[1].toInt() and 0xFF
            if (bpm in 30..220) {
                log("SIG Heart Rate: $bpm BPM")
                emit(mapOf("type" to "telemetry", "heartRate" to bpm))
            }
            return
        }

        // 3. MediaTek PDMS Pedometer (0x2AAA)
        if (uuid == CH_PDMS && data.size >= 20) {
            val dataType = (data[0].toInt() and 0xFF) or ((data[1].toInt() and 0xFF) shl 8)
            if (dataType == 10) {
                val steps = (data[6].toInt() and 0xFF) or
                        ((data[7].toInt() and 0xFF) shl 8) or
                        ((data[8].toInt() and 0xFF) shl 16) or
                        ((data[9].toInt() and 0xFF) shl 24)
                val cal = (data[14].toInt() and 0xFF) or
                        ((data[15].toInt() and 0xFF) shl 8) or
                        ((data[16].toInt() and 0xFF) shl 16) or
                        ((data[17].toInt() and 0xFF) shl 24)
                val distMeters = (data[18].toInt() and 0xFF) or ((data[19].toInt() and 0xFF) shl 8)
                log("PDMS Sync: Steps=$steps, Cal=$cal, Dist=${distMeters}m")
                emit(
                    mapOf(
                        "type" to "telemetry",
                        "steps" to steps,
                        "calories" to cal,
                        "distanceKm" to (distMeters / 1000.0)
                    )
                )
            }
            return
        }

        // 4. Check for raw "ios indication" prompt on 2ABC / 2AA0
        val ascii = String(data.filter { it in 32..126 }.toByteArray(), Charsets.UTF_8)
        if (ascii.contains("ios indication")) {
            log("RX [$shortUuid]: ios indication -> replying with MTK time sync")
            onCtsSyncRequested?.invoke(!is24Hour)
            syncTime(is24Hour)
            return
        }

        // 5. Feed into MediaTek F0F0F0F1 RC4 StreamParser
        val frames = parser.feed(data)
        if (frames.isEmpty()) {
            log("RX [$shortUuid]: $hex")
            return
        }

        for (frame in frames) {
            val hdr = frame.headerText
            val body = frame.payloadText.trim()
            log("RX [MTK t=${frame.cmdType}]: $hdr | $body")

            when (frame.cmdType) {
                MtkCodec.T_ACKY -> {
                    log("MTK Handshake Type 3 (ACKY) received")
                    syncTime(is24Hour)
                }
                MtkCodec.T_VERN -> {
                    log("MTK Version Handshake Type 4 received: $body")
                    syncTime(is24Hour)
                }
                else -> {
                    if (hdr.contains("bnsrv_time") || body.contains("bnsrv_time")) {
                        write(MtkCodec.encodeSyncTime(is24Hour, useNewFormat = true))
                    } else if (hdr.contains("mtk_language") || body.contains("mtk_language")) {
                        val lb = "en_US".toByteArray(Charsets.UTF_8)
                        write(MtkCodec.encodePacket(MtkCodec.T_EXCD, "language mtk_language 1 0 ${lb.size} ", lb))
                    }
                    parseWwPayload(body.ifEmpty { hdr })
                }
            }
        }
    }

    private fun parseWwPayload(text: String) {
        if (text.isEmpty()) return

        emit(mapOf("type" to "rx", "text" to text))

        // Watch Find Phone triggers
        if (text.contains("10,4,1")) {
            log("WATCH TRIGGERED FIND PHONE!")
            onStartPhoneAlarm?.invoke()
            emit(mapOf("type" to "findPhone", "ringing" to true))
            return
        }
        if (text.contains("10,4,0")) {
            log("Watch stopped Find Phone")
            onStopPhoneAlarm?.invoke()
            emit(mapOf("type" to "findPhone", "ringing" to false))
            return
        }

        val cleaned = text.substringAfterLast(" ").trim()
        val parts = cleaned.split(",")
        if (parts.size < 2) return

        val cmd = parts[0]
        val sub = parts[1]

        when (cmd) {
            "01" -> {
                // Device info or step summary
                if (parts.size >= 4) {
                    val steps = parts[2].toIntOrNull()
                    val cal = parts[3].toIntOrNull()
                    if (steps != null) {
                        emit(
                            mapOf(
                                "type" to "telemetry",
                                "steps" to steps,
                                "calories" to (cal ?: (steps * 0.04).toInt()),
                                "distanceKm" to (steps * 0.00075)
                            )
                        )
                    }
                }
                sendWw("01,8")
            }
            "03" -> {
                // Steps / Sport records: 03,1,<steps>,<distance>,<calories> or pipe-separated records
                val payloadStr = parts.drop(2).joinToString(",")
                val firstRec = payloadStr.split("|", ";").firstOrNull() ?: payloadStr
                val fields = firstRec.split(",", ":")
                val steps = fields.firstOrNull()?.toIntOrNull() ?: parts.getOrNull(2)?.toIntOrNull()
                if (steps != null && steps >= 0) {
                    val cal = fields.getOrNull(2)?.toIntOrNull() ?: (steps * 0.04).toInt()
                    val dist = fields.getOrNull(1)?.toDoubleOrNull() ?: (steps * 0.00075)
                    log("Steps synced: $steps")
                    emit(
                        mapOf(
                            "type" to "telemetry",
                            "steps" to steps,
                            "calories" to cal,
                            "distanceKm" to dist
                        )
                    )
                }
                if (sub == "1" || sub == "2") sendWw("03,3")
            }
            "04" -> {
                // Sleep data
                val mins = parts.getOrNull(2)?.toDoubleOrNull()
                if (mins != null && mins > 0) {
                    val hours = if (mins > 24.0) (mins / 60.0) else mins
                    emit(mapOf("type" to "telemetry", "sleepHours" to hours))
                }
                if (sub == "1" || sub == "2") sendWw("04,3")
            }
            "05" -> {
                // Heart rate data (05,1,<bpm> or timestamp|bpm)
                val raw = parts.drop(2).joinToString(",")
                val numbers = Regex("\\b([4-9]\\d|1\\d\\d|20\\d)\\b")
                    .findAll(raw)
                    .mapNotNull { it.value.toIntOrNull() }
                    .toList()
                val bpm = numbers.lastOrNull() ?: parts.getOrNull(2)?.toIntOrNull()
                if (bpm != null && bpm in 35..215) {
                    log("Heart Rate synced: $bpm BPM")
                    emit(mapOf("type" to "telemetry", "heartRate" to bpm))
                }
                if (sub == "1" || sub == "2") sendWw("05,3")
            }
            "11" -> {
                // Battery / status response
                val v = parts.getOrNull(2)?.toIntOrNull()
                if (v != null && v in 0..100) {
                    emit(mapOf("type" to "telemetry", "battery" to v))
                }
            }
            "13" -> {
                // Blood pressure (13,1,<sys>,<dia>)
                val nums = parts.drop(2)
                    .flatMap { it.split("|", ":", ";") }
                    .mapNotNull { it.toIntOrNull() }
                    .filter { it in 40..220 }
                if (nums.size >= 2) {
                    emit(
                        mapOf(
                            "type" to "telemetry",
                            "systolicBp" to nums[0],
                            "diastolicBp" to nums[1]
                        )
                    )
                }
                if (sub == "1" || sub == "2") sendWw("13,3")
            }
            "14" -> {
                // Body temperature (14,1,<temp>)
                val rawTemp = parts.getOrNull(2)?.split("|")?.lastOrNull()?.toDoubleOrNull()
                if (rawTemp != null && rawTemp > 0) {
                    val tempC = if (rawTemp > 100) rawTemp / 10.0 else rawTemp
                    emit(mapOf("type" to "telemetry", "bodyTemp" to tempC))
                }
                if (sub == "1" || sub == "2") sendWw("14,3")
            }
            "15" -> {
                // Immunity / SpO2
                val imm = parts.getOrNull(2)?.split("|")?.lastOrNull()?.toIntOrNull()
                if (imm != null && imm in 1..100) {
                    emit(mapOf("type" to "telemetry", "immunity" to imm))
                }
                if (sub == "1" || sub == "2") sendWw("15,3")
            }
        }
    }

    // ---- Outgoing Command Builders & Senders ----

    fun sendWw(cmd: String): Boolean {
        if (!isConnected || cmd.isEmpty()) return false
        val frame = MtkCodec.encodeWw(cmd)
        log("TX [WW]: $cmd")
        return write(frame)
    }

    fun sendPedometer(cmd: String = "GET,0"): Boolean {
        if (!isConnected) return false
        val frame = MtkCodec.encodePedometer(cmd)
        log("TX [PEDO]: $cmd")
        return write(frame)
    }

    fun syncTime(use24Hour: Boolean? = null): Boolean {
        if (use24Hour != null) {
            is24Hour = use24Hour
            prefs.edit().putBoolean("is24Hour", is24Hour).apply()
        }
        onCtsSyncRequested?.invoke(!is24Hour)
        if (!isConnected) return false

        write(MtkCodec.encodeSyncTime(is24Hour, useNewFormat = false))
        write(MtkCodec.encodeSyncTime(is24Hour, useNewFormat = true))
        sendWw(if (is24Hour) "SET,40,1" else "SET,40,0")
        log("Synced time (${if (is24Hour) "24-Hour" else "12-Hour"} mode)")
        return true
    }

    fun readBattery() {
        val g = gatt ?: return
        val bc = battChar
        if (bc != null) {
            enqueueOp {
                if (!g.readCharacteristic(bc)) {
                    completeOp()
                }
            }
        }
        if (isConnected) {
            sendWw("11,1")
        }
    }

    fun immediateAlert(level: Int = 2) {
        val g = gatt
        val ac = alertChar
        if (g != null && ac != null) {
            enqueueOp {
                ac.value = byteArrayOf(level.toByte())
                ac.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                if (!g.writeCharacteristic(ac)) {
                    completeOp()
                }
            }
        }
        if (isConnected) {
            sendWw("12,4,1")
        }
        log("Dispatched Find Watch alert")
    }

    fun pushNotification(pkg: String, title: String, body: String, isCall: Boolean = false): Boolean {
        if (!isConnected) return false
        val id = msgIdCounter++
        val packet = MtkCodec.encodeNotificationXml(id, pkg, title, body, isCall)
        log("TX [NOTIF]: $title - $body")
        return write(packet)
    }

    fun pushWeather(city: String, conditionCode: Int, currentTemp: Int, highTemp: Int, lowTemp: Int): Boolean {
        if (!isConnected) return false
        val packet = MtkCodec.encodeWeather(city, conditionCode, currentTemp, highTemp, lowTemp)
        log("TX [WEATHER]: $city $currentTemp°C ($lowTemp°/$highTemp°)")
        return write(packet)
    }

    /**
     * Slices any outgoing frame into 20-byte BLE packets and queues them sequentially
     * on characteristic 0x2AA1 using WRITE_TYPE_DEFAULT (or WRITE_TYPE_NO_RESPONSE if required).
     */
    fun write(bytes: ByteArray): Boolean {
        val g = gatt ?: return false
        val wc = writeChar ?: return false
        if (!isConnected || bytes.isEmpty()) return false

        var offset = 0
        while (offset < bytes.size) {
            val end = (offset + chunkSize).coerceAtMost(bytes.size)
            val slice = bytes.copyOfRange(offset, end)
            offset = end

            enqueueOp {
                val curGatt = gatt
                val curChar = writeChar
                if (curGatt == null || curChar == null || !isConnected) {
                    completeOp()
                } else {
                    curChar.value = slice
                    val supportsWrite = (curChar.properties and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0
                    curChar.writeType = if (supportsWrite) {
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    } else {
                        BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    }
                    if (!curGatt.writeCharacteristic(curChar)) {
                        completeOp()
                    }
                }
            }
        }
        return true
    }
}