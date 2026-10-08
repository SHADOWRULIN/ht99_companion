import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_model.dart';
import 'mtk_protocol.dart';

class WatchBleService {
  static const MethodChannel _ctsChannel =
      MethodChannel("com.ht99.companion/cts");

  BluetoothDevice? device;
  BluetoothCharacteristic? writeChar; // 0x2AA1
  BluetoothCharacteristic? notifyChar; // 0x2AA0 or 0x2ABC
  BluetoothCharacteristic? alertChar; // 0x2A06
  BluetoothCharacteristic? batteryChar; // 0x2A19

  StreamSubscription? _scanSub;
  final List<StreamSubscription> _notifySubs = [];

  final TelemetryModel telemetry = TelemetryModel();
  final List<String> logs = [];

  bool isConnecting = false;
  bool isConnected = false;

  void Function(String)? onStatus;
  void Function()? onData;
  void Function()? onConnected;

  void log(String msg) {
    String ts = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, "[$ts] $msg");
    if (logs.length > 200) logs.removeLast();
    onData?.call();
  }

  Future<void> scanAndConnect() async {
    if (isConnecting || isConnected) {
      log("Connection in progress or already connected. Skipping duplicate scan.");
      return;
    }
    isConnecting = true;

    log("Ensuring CTS GATT Server...");
    try {
      await _ctsChannel.invokeMethod("startCtsServer");
    } catch (_) {}

    onStatus?.call("Scanning for HT99...");
    log("Scanning for HT99...");

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      log("Scan error: $e");
      onStatus?.call("Scan error: $e");
      isConnecting = false;
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.platformName.toUpperCase();
        String mac = r.device.remoteId.str.toUpperCase();

        if (name.contains("HT99") ||
            mac.contains("F9:47") ||
            mac.contains("CC:76") ||
            mac.contains("FC:84") ||
            mac.contains("D0:CC")) {
          log("Acquired target: $name [$mac]");
          onStatus?.call("Found HT99. Binding...");

          // Stop scan immediately to prevent duplicate connect events
          await stopScan();
          await _bind(r.device);
          break;
        }
      }
    });
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;
    } catch (_) {}
  }

  Future<void> _bind(BluetoothDevice target) async {
    try {
      await target.connect(
        license: License.nonprofit,
        autoConnect: false,
        mtu: 256,
      );
      device = target;
      isConnected = true;
      isConnecting = false;
      log("Connected. Discovering services...");

      List<BluetoothService> services = await target.discoverServices();

      for (var s in services) {
        for (var c in s.characteristics) {
          String u = c.uuid.str.toLowerCase();

          if (u.contains("2aa1") ||
              c.properties.write ||
              c.properties.writeWithoutResponse) {
            writeChar ??= c;
          }
          if (u.contains("2aa0") || u.contains("2abc")) {
            notifyChar ??= c;
          }
          if (u.contains("2a06")) alertChar = c;
          if (u.contains("2a19")) batteryChar = c;

          if (c.properties.notify || c.properties.indicate) {
            try {
              await c.setNotifyValue(true);
              var sub =
                  c.lastValueStream.listen((data) => _parseIncoming(u, data));
              _notifySubs.add(sub);
            } catch (_) {}
          }
        }
      }

      log("Endpoints acquired. Initializing WWfit link...");
      onStatus?.call("Connected & Initialized");
      onConnected?.call();

      // 1. Send WWfit Identification Handshake (turns watch icon BLUE and stops disconnects)
      for (var frame in MtkProtocol.buildWwfitHandshake()) {
        await writeRaw(frame);
        await Future.delayed(const Duration(milliseconds: 25));
      }

      // 2. Sync Phone Time and 12-Hour format
      await syncClock(telemetry.is12Hour);

      // 3. Query initial telemetry
      await queryPedometer();
      await readSigBattery();
    } catch (e) {
      log("Bind error: $e");
      onStatus?.call("Bind failed");
      isConnecting = false;
      isConnected = false;
    }
  }

  void _parseIncoming(String uuid, List<int> data) {
    if (data.isEmpty) return;
    String hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    log("RX [$uuid]: $hex");

    // Standard KCT health response (Header 0xAB)
    if (data[0] == 0xAB && data.length >= 4) {
      int cmd = data[2];
      if (cmd == 0x91 || cmd == 0x08) {
        telemetry.batteryLevel = data[3].clamp(0, 100);
        log("Telemetry: Battery = ${telemetry.batteryLevel}%");
        onData?.call();
      } else if (cmd == 0x51 && data.length >= 7) {
        telemetry.steps = (data[4] << 16) | (data[5] << 8) | data[6];
        telemetry.calories = (telemetry.steps * 0.04).round();
        telemetry.distanceKm = (telemetry.steps * 0.00075);
        log("Telemetry: Steps = ${telemetry.steps}");
        onData?.call();
      } else if (cmd == 0x82 && data.length >= 4) {
        telemetry.heartRate = data[3];
        log("Telemetry: HeartRate = ${telemetry.heartRate} BPM");
        onData?.call();
      }
    }

    // ASCII string telemetry
    String text = String.fromCharCodes(data.where((b) => b >= 32 && b <= 126));
    if (text.contains("ios indication")) {
      log("CTS Verification requested. Re-broadcasting time...");
      syncClock(telemetry.is12Hour);
    }
  }

  Future<void> syncClock(bool is12Hour) async {
    telemetry.is12Hour = is12Hour;

    // 1. Android CTS Native Server broadcast
    try {
      await _ctsChannel.invokeMethod("broadcastCtsTime");
      await _ctsChannel.invokeMethod("setTimeFormat", {"is12Hour": is12Hour});
    } catch (_) {}

    // 2. Set watch RTC clock via KCT time packet
    await writeRaw(MtkProtocol.buildKctTimePacket(DateTime.now()));
    await Future.delayed(const Duration(milliseconds: 30));

    // 3. Set watch 12h/24h toggle via WWfit SET,40 command
    await writeRaw(MtkProtocol.buildTimeFormatCmd(is12Hour));
    log("Dispatched Time Sync (12h=$is12Hour)");
    onData?.call();
  }

  Future<void> queryPedometer() async {
    await writeRaw(MtkProtocol.buildPedometerQuery());
    await Future.delayed(const Duration(milliseconds: 30));
    await writeRaw(MtkProtocol.buildKctStepQuery());
    log("Dispatched pedometer query");
  }

  Future<void> readSigBattery() async {
    if (batteryChar != null) {
      try {
        var v = await batteryChar!.read();
        if (v.isNotEmpty) {
          telemetry.batteryLevel = v[0];
          log("SIG Battery: ${telemetry.batteryLevel}%");
          onData?.call();
        }
      } catch (_) {}
    }
    await writeRaw(MtkProtocol.buildBatteryQuery());
  }

  Future<void> ringWatch() async {
    if (alertChar != null) {
      try {
        await alertChar!.write([0x02], withoutResponse: true);
      } catch (_) {}
    }
    await writeRaw(MtkProtocol.buildFindWatch());
    log("Dispatched Find Watch command");
  }

  Future<void> pushNotification(String title, String body) async {
    await writeRaw(MtkProtocol.buildNotificationPacket(title, body));
    log("Dispatched Notification: $title");
  }

  Future<void> pushWeather(
      int tempC, int conditionCode, int highC, int lowC) async {
    await writeRaw(
        MtkProtocol.buildWeatherPacket(tempC, conditionCode, highC, lowC));
    log("Dispatched Weather: $tempC°C (High: $highC, Low: $lowC)");
  }

  Future<bool> writeRaw(List<int> bytes) async {
    if (writeChar == null || device == null) return false;
    const int chunkSize = 20;

    try {
      if (bytes.length <= chunkSize) {
        await writeChar!.write(
          bytes,
          withoutResponse: writeChar!.properties.writeWithoutResponse,
        );
        return true;
      }

      for (int i = 0; i < bytes.length; i += chunkSize) {
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        List<int> chunk = bytes.sublist(i, end);
        await writeChar!.write(
          chunk,
          withoutResponse: writeChar!.properties.writeWithoutResponse,
        );
        await Future.delayed(const Duration(milliseconds: 18));
      }
      return true;
    } catch (e) {
      log("Write exception: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    for (var s in _notifySubs) {
      await s.cancel();
    }
    _notifySubs.clear();
    await device?.disconnect();
    device = null;
    writeChar = null;
    notifyChar = null;
    alertChar = null;
    batteryChar = null;
    isConnected = false;
    isConnecting = false;
    log("Watch disconnected");
    onStatus?.call("Disconnected");
    onData?.call();
  }
}
