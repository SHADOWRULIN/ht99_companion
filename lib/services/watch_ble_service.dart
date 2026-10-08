import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/watch_telemetry.dart';
import 'watch_protocol.dart';

class WatchBleService {
  static const MethodChannel _ctsChannel =
      MethodChannel("com.ht99.companion/cts");

  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? dogpWriteChar; // 0x2AA1
  BluetoothCharacteristic? timeFormatChar; // 0x2B01
  BluetoothCharacteristic? pdmsChar; // 0x2AAA
  BluetoothCharacteristic? hrChar; // 0x2A37
  BluetoothCharacteristic? alertChar; // 0x2A06
  BluetoothCharacteristic? batteryChar; // 0x2A19

  StreamSubscription? _scanSub;
  final List<StreamSubscription> _notifySubs = [];

  final WatchTelemetry telemetry = WatchTelemetry();
  final List<String> logs = [];

  void Function(String)? onStatusUpdate;
  void Function()? onDataUpdate;
  void Function()? onConnectedCallback;

  void log(String message) {
    String time = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, "[$time] $message");
    if (logs.length > 150) logs.removeLast();
    onDataUpdate?.call();
  }

  Future<void> startScan() async {
    log("Requesting CTS GATT Server start...");
    try {
      await _ctsChannel.invokeMethod("startCtsServer");
    } catch (_) {}

    log("Scanning for HT99 BLE beacon...");
    onStatusUpdate?.call("Scanning for HT99...");

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      log("Scan error: $e");
      onStatusUpdate?.call("Bluetooth Scan Failed");
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.platformName.toUpperCase();
        String mac = r.device.remoteId.str.toUpperCase();

        if (name.contains("HT99") ||
            mac.contains("F9:47") ||
            mac.contains("CC:76") ||
            mac.contains("F9:9B")) {
          log("Acquired target: $name [$mac]");
          onStatusUpdate?.call("Found HT99. Binding...");
          await stopScan();
          await _bindDevice(r.device);
          break;
        }
      }
    });
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
    } catch (_) {}
  }

  Future<void> _bindDevice(BluetoothDevice device) async {
    try {
      await device.connect(license: License.free, autoConnect: false, mtu: 256);
      targetDevice = device;
      log("GATT Connected. Resolving services...");

      List<BluetoothService> services = await device.discoverServices();

      for (var s in services) {
        for (var c in s.characteristics) {
          String u = c.uuid.str.toLowerCase();

          if (u.contains("2aa1")) dogpWriteChar = c;
          if (u.contains("2b01")) timeFormatChar = c;
          if (u.contains("2aaa")) pdmsChar = c;
          if (u.contains("2a37")) hrChar = c;
          if (u.contains("2a06")) alertChar = c;
          if (u.contains("2a19")) batteryChar = c;

          if (u.contains("2abc") || u.contains("2aaa") || u.contains("2a37")) {
            try {
              await c.setNotifyValue(true);
              var sub =
                  c.lastValueStream.listen((data) => _parseIncoming(u, data));
              _notifySubs.add(sub);
            } catch (_) {}
          }
        }
      }

      log("Bound endpoints: DOGP, TimeFormat, PDMS, HR");
      onStatusUpdate?.call("Connected & Bound");
      onConnectedCallback?.call();

      await setupWatchParameters();
    } catch (e) {
      log("Connection failed: $e");
      onStatusUpdate?.call("Failed to connect");
    }
  }

  void _parseIncoming(String uuid, List<int> data) {
    if (data.isEmpty) return;
    String hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    log("RX [$uuid]: $hex");

    // Check for iOS Indication inquiry
    String ascii = String.fromCharCodes(data.where((b) => b >= 32 && b <= 126));
    if (ascii.contains("ios indication")) {
      log("Watch requested CTS link verification. Replying...");
      writeRaw(WatchProtocol.buildHandshakeAck());
      syncPhoneTime();
      return;
    }

    // Pedometer Data Parsing (from pdms.c)
    if (uuid.contains("2aaa") && data.length >= 20) {
      int type = (data[0] & 0xFF) | ((data[1] & 0xFF) << 8);
      if (type == 10) {
        telemetry.steps = (data[6] & 0xFF) |
            ((data[7] & 0xFF) << 8) |
            ((data[8] & 0xFF) << 16) |
            ((data[9] & 0xFF) << 24);
        telemetry.calories = (data[14] & 0xFF) |
            ((data[15] & 0xFF) << 8) |
            ((data[16] & 0xFF) << 16) |
            ((data[17] & 0xFF) << 24);
        int distMeters = (data[18] & 0xFF) | ((data[19] & 0xFF) << 8);
        telemetry.distanceKm = distMeters / 1000.0;
        log("Parsed PDMS: Steps=${telemetry.steps}, Cal=${telemetry.calories}, Dist=${telemetry.distanceKm}km");
        onDataUpdate?.call();
      }
    }

    // Heart Rate Parsing (from hr.c)
    if (uuid.contains("2a37") && data.length >= 2) {
      telemetry.heartRate = data[1] & 0xFF;
      log("Parsed Heart Rate: ${telemetry.heartRate} BPM");
      onDataUpdate?.call();
    }
  }

  Future<void> setupWatchParameters() async {
    // 1. Enforce 12-Hour format
    await setTimeFormat(telemetry.is12HourFormat);

    // 2. Activate PDMS Step tracking
    if (pdmsChar != null) {
      await pdmsChar!.write(WatchProtocol.buildPdmsActivationPayload(10),
          withoutResponse: true);
      log("PDMS Step interval set (10s)");
    }

    // 3. Read SIG Battery
    if (batteryChar != null) {
      try {
        var v = await batteryChar!.read();
        if (v.isNotEmpty) {
          telemetry.batteryLevel = v[0];
          onDataUpdate?.call();
        }
      } catch (_) {}
    }

    // 4. Synchronize clock
    await syncPhoneTime();
  }

  Future<void> setTimeFormat(bool is12Hour) async {
    telemetry.is12HourFormat = is12Hour;
    if (timeFormatChar != null) {
      try {
        await timeFormatChar!.write(
            WatchProtocol.buildTimeFormatPayload(is12Hour),
            withoutResponse: true);
        log("Time format written: ${is12Hour ? '12-Hour' : '24-Hour'}");
      } catch (e) {
        log("TimeFormat write error: $e");
      }
    }
    onDataUpdate?.call();
  }

  Future<void> syncPhoneTime() async {
    try {
      await _ctsChannel.invokeMethod("broadcastCtsTime");
      log("Dispatched CTS Native Broadcast");
    } catch (_) {}

    DateTime now = DateTime.now();
    List<int> kctTime = [
      0xAB,
      0x00,
      0x04,
      (now.year >> 8) & 0xFF,
      now.year & 0xFF,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    ];
    await writeRaw(kctTime);
  }

  Future<void> ringWatch() async {
    if (alertChar != null) {
      try {
        await alertChar!.write([0x02], withoutResponse: true);
        log("Immediate Alert (0x02) written");
      } catch (_) {}
    }
  }

  Future<void> sendNotification(String title, String body) async {
    List<int> payload =
        WatchProtocol.buildNotificationFrame(1, title, body, "Companion");
    await writeRaw(payload);
    log("XML Notification payload dispatched");
  }

  Future<bool> writeRaw(List<int> bytes) async {
    if (dogpWriteChar == null) return false;
    const int chunk = 20;
    try {
      for (int i = 0; i < bytes.length; i += chunk) {
        int end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
        await dogpWriteChar!.write(bytes.sublist(i, end),
            withoutResponse: dogpWriteChar!.properties.writeWithoutResponse);
        await Future.delayed(const Duration(milliseconds: 15));
      }
      return true;
    } catch (e) {
      log("Write error: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    for (var s in _notifySubs) {
      await s.cancel();
    }
    _notifySubs.clear();
    await targetDevice?.disconnect();
    targetDevice = null;
    dogpWriteChar = null;
    timeFormatChar = null;
    pdmsChar = null;
    hrChar = null;
    alertChar = null;
    batteryChar = null;
    log("Watch disconnected");
    onStatusUpdate?.call("Disconnected");
  }
}
