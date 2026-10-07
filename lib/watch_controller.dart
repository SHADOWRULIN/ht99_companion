import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WatchController {
  static const MethodChannel _ctsChannel =
      MethodChannel("com.ht99.companion/cts");

  BluetoothDevice? device;
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? alertChar;
  BluetoothCharacteristic? batteryChar;
  BluetoothCharacteristic? hrChar;

  StreamSubscription? _scanSub;
  StreamSubscription? _notifySub;

  int batteryLevel = 50;
  int stepCount = 0;
  int heartRate = 0;
  double distanceKm = 0.0;
  int caloriesKcal = 0;

  final List<String> logs = [];

  void log(String msg) {
    String ts = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, "[$ts] $msg");
    if (logs.length > 80) logs.removeLast();
  }

  Future<void> connect({
    required Function(String) onStatus,
    required Function() onConnected,
    required Function() onData,
  }) async {
    onStatus("Scanning for HT99...");
    log("Scanning for watch advertisements...");

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      onStatus("Scan failed: $e");
      log("Scan error: $e");
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.platformName.toUpperCase();
        String mac = r.device.remoteId.str.toUpperCase();

        if (name.contains("HT99") ||
            mac.contains("F9:47") ||
            mac.contains("CC:76")) {
          onStatus("Found HT99 ($mac). Binding...");
          log("Acquired device: $name [$mac]");
          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();

          await _bind(r.device, onStatus, onConnected, onData);
          break;
        }
      }
    });
  }

  Future<void> _bind(
    BluetoothDevice target,
    Function(String) onStatus,
    Function() onConnected,
    Function() onData,
  ) async {
    try {
      await target.connect(
        license: License.free,
        autoConnect: false,
        mtu: 256,
      );
      device = target;
      log("Connected. Inspecting GATT services...");

      List<BluetoothService> services = await target.discoverServices();

      for (var s in services) {
        for (var c in s.characteristics) {
          String uuid = c.uuid.str.toLowerCase();

          // 1. Immediate Alert (0x2A06)
          if (uuid.contains("2a06")) {
            alertChar = c;
            log("Bound Alert (2a06)");
          }
          // 2. Battery Service (0x2A19)
          else if (uuid.contains("2a19")) {
            batteryChar = c;
            log("Bound Battery (2a19)");
          }
          // 3. Heart Rate Service (0x2A37)
          else if (uuid.contains("2a37")) {
            hrChar = c;
            log("Bound Heart Rate (2a37)");
          }
          // 4. Vendor Data Pipes (2aa1, KCT)
          else if (c.properties.write || c.properties.writeWithoutResponse) {
            writeChar = c;
            log("Bound Data Write: $uuid");
          }

          if (c.properties.notify || c.properties.indicate) {
            try {
              await c.setNotifyValue(true);
              c.lastValueStream.listen((data) => _parseIncoming(data, onData));
            } catch (_) {}
          }
        }
      }

      onStatus("Connected & Synchronized");
      onConnected();

      // Read initial battery
      await readBattery(onData);

      // Trigger automatic CTS clock synchronization
      await syncTime();
    } catch (e) {
      onStatus("Connection error: $e");
      log("Bind exception: $e");
    }
  }

  void _parseIncoming(List<int> data, Function() onData) {
    if (data.isEmpty) return;
    String hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    log("RX: $hex");

    // Standard Health / Step Packet Parsing
    if (data[0] == 0xAB && data.length >= 4) {
      int cmd = data[2];
      if (cmd == 0x91 || cmd == 0x08) {
        batteryLevel = data[3].clamp(0, 100);
        onData();
      } else if (cmd == 0x51 && data.length >= 7) {
        stepCount = (data[4] << 16) | (data[5] << 8) | data[6];
        distanceKm = (stepCount * 0.00075);
        caloriesKcal = (stepCount * 0.04).round();
        onData();
      }
    }
  }

  // Dual-Engine Time Sync: CTS Phone Server + Direct Vendor Packet
  Future<void> syncTime() async {
    // 1. Trigger Android Native CTS GATT Server broadcast
    try {
      await _ctsChannel.invokeMethod("broadcastCtsTime");
      log("CTS Server broadcast dispatched to watch");
    } catch (e) {
      log("CTS native broadcast notice: $e");
    }

    // 2. Direct Vendor Fallback Packets
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

    List<int> mtkTime = [
      0xEA,
      0x01,
      0x01,
      now.year % 100,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    ];
    await writeRaw(mtkTime);
  }

  // Trigger Watch Vibration / Find Watch
  Future<void> ringWatch() async {
    if (alertChar != null) {
      try {
        await alertChar!.write([0x02], withoutResponse: true);
        log("Sent High Alert (0x02) to 2a06");
      } catch (e) {
        log("Alert write error: $e");
      }
    }
    await writeRaw([0xAB, 0x00, 0x03, 0x01]);
  }

  // Read Battery Level from 0x2A19
  Future<void> readBattery(Function() onData) async {
    if (batteryChar != null) {
      try {
        var v = await batteryChar!.read();
        if (v.isNotEmpty) {
          batteryLevel = v[0];
          log("SIG Battery: $batteryLevel%");
          onData();
        }
      } catch (_) {}
    }
  }

  // Send Push Notification Text
  Future<void> sendNotification(String title, String body) async {
    List<int> t = title.codeUnits;
    List<int> b = body.codeUnits;
    List<int> packet = [
      0xAB,
      0x00,
      0x02,
      0x01,
      t.length,
      ...t,
      b.length,
      ...b,
    ];
    log("TX Notification: $title - $body");
    await writeRaw(packet);
  }

  // Hardware Feature Toggles
  Future<void> setWaterReminder(bool enable) async {
    await writeRaw([0xAB, 0x00, 0x12, enable ? 0x01 : 0x00]);
    log("Water Reminder set: $enable");
  }

  Future<void> setSedentaryReminder(bool enable) async {
    await writeRaw([0xAB, 0x00, 0x13, enable ? 0x01 : 0x00]);
    log("Sedentary Reminder set: $enable");
  }

  Future<void> triggerHeartRateMeasure() async {
    await writeRaw([0xAB, 0x00, 0x82, 0x01]);
    log("Heart Rate Measurement initiated");
  }

  Future<bool> writeRaw(List<int> bytes) async {
    if (writeChar == null) return false;
    try {
      await writeChar!.write(
        bytes,
        withoutResponse: writeChar!.properties.writeWithoutResponse,
      );
      return true;
    } catch (e) {
      log("Write raw error: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await device?.disconnect();
    device = null;
    writeChar = null;
    alertChar = null;
    batteryChar = null;
    log("Disconnected");
  }
}
