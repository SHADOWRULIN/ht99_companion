import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WatchController {
  static const MethodChannel _ctsChannel =
      MethodChannel("com.ht99.companion/cts");

  BluetoothDevice? device;
  BluetoothCharacteristic? dogpWriteChar; // 2aa1
  BluetoothCharacteristic? dogpNotifyChar; // 2abc
  BluetoothCharacteristic? alertChar; // 2a06
  BluetoothCharacteristic? batteryChar; // 2a19

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
    if (logs.length > 100) logs.removeLast();
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
    } catch (_) {}
  }

  Future<void> connect({
    required Function(String) onStatus,
    required Function() onConnected,
    required Function() onData,
  }) async {
    onStatus("Initializing Bluetooth...");
    log("Checking adapter state...");

    try {
      await _ctsChannel.invokeMethod("startCtsServer");
      log("Native CTS Server initialized");
    } catch (e) {
      log("CTS initialization notice: $e");
    }

    onStatus("Scanning for HT99...");
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
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
            mac.contains("CC:76") ||
            mac.contains("F9:9B")) {
          onStatus("Found HT99 ($mac). Connecting...");
          log("Target acquired: $name [$mac]");
          await stopScan();
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
      log("Connected! Inspecting services...");

      List<BluetoothService> services = await target.discoverServices();

      for (var s in services) {
        for (var c in s.characteristics) {
          String u = c.uuid.str.toLowerCase();

          // 1. Immediate Alert (0x2A06)
          if (u.contains("2a06")) {
            alertChar = c;
            log("Bound Alert (2a06)");
          }
          // 2. Battery (0x2A19)
          else if (u.contains("2a19")) {
            batteryChar = c;
            log("Bound Battery (2a19)");
          }
          // 3. MediaTek DOGP Channel (18a0 / 2aa1)
          else if (u.contains("2aa1") ||
              c.properties.write ||
              c.properties.writeWithoutResponse) {
            dogpWriteChar ??= c;
            log("Bound DOGP Write: $u");
          }

          // 4. MediaTek DOGP Notify Channel (2abc)
          if (u.contains("2abc") ||
              c.properties.notify ||
              c.properties.indicate) {
            dogpNotifyChar ??= c;
            try {
              await c.setNotifyValue(true);
              _notifySub = c.lastValueStream
                  .listen((data) => _parseIncoming(data, onData));
              log("Subscribed to stream: $u");
            } catch (_) {}
          }
        }
      }

      onStatus("Connected & Synchronized");
      onConnected();

      // Read battery level and sync clock
      await readBattery(onData);
      await syncTime();
    } catch (e) {
      onStatus("Binding failed: $e");
      log("Binding exception: $e");
    }
  }

  void _parseIncoming(List<int> data, Function() onData) {
    if (data.isEmpty) return;
    String hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    log("RX: $hex");

    String ascii = String.fromCharCodes(data.where((b) => b >= 32 && b <= 126));
    if (ascii.contains("ios indication")) {
      log("Watch requested iOS/CTS verification. Broadcasting time...");
      syncTime();
      return;
    }

    // Packet decoders
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

  // Triple-Channel Clock Synchronization
  Future<void> syncTime() async {
    // 1. Native CTS GATT Server Broadcast
    try {
      await _ctsChannel.invokeMethod("broadcastCtsTime");
      log("CTS Server time broadcasted");
    } catch (e) {
      log("CTS broadcast notice: $e");
    }

    // 2. KCT Frame: 0xAB 0x00 0x04 [YYYY] [MM] [DD] [hh] [mm] [ss]
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

    // 3. MediaTek ASCII String Sync (from DataSyncController)
    String mtkTimeStr =
        "time ${now.year} ${now.month} ${now.day} ${now.hour} ${now.minute} ${now.second}\n";
    await writeRaw(mtkTimeStr.codeUnits);
  }

  Future<void> ringWatch() async {
    if (alertChar != null) {
      try {
        await alertChar!.write([0x02], withoutResponse: true);
        log("TX Immediate Alert: 0x02");
      } catch (_) {}
    }
    await writeRaw([0xAB, 0x00, 0x03, 0x01]);
  }

  Future<void> readBattery(Function() onData) async {
    if (batteryChar != null) {
      try {
        var v = await batteryChar!.read();
        if (v.isNotEmpty) {
          batteryLevel = v[0];
          log("SIG Battery level: $batteryLevel%");
          onData();
        }
      } catch (_) {}
    }
    await writeRaw([0xAB, 0x00, 0x91]); // KCT Battery Query
  }

  Future<void> sendNotification(String title, String body) async {
    List<int> t = title.codeUnits;
    List<int> b = body.codeUnits;
    List<int> packet = [0xAB, 0x00, 0x02, 0x01, t.length, ...t, b.length, ...b];
    log("TX Notification: $title");
    await writeRaw(packet);
  }

  // Dial Push Framework (streams 320x385 .dat packets in 20-byte chunks)
  Future<void> pushDial(List<int> datBytes, Function(double) onProgress) async {
    log("Starting Dial Push (${datBytes.length} bytes)...");
    const int chunkSize = 20;
    int total = datBytes.length;

    for (int i = 0; i < total; i += chunkSize) {
      int end = (i + chunkSize < total) ? i + chunkSize : total;
      await writeRaw(datBytes.sublist(i, end));
      onProgress(end / total);
      await Future.delayed(const Duration(milliseconds: 15));
    }
    log("Dial Push Completed!");
  }

  Future<void> setWaterReminder(bool enable) async {
    await writeRaw([0xAB, 0x00, 0x12, enable ? 0x01 : 0x00]);
  }

  Future<void> setSedentaryReminder(bool enable) async {
    await writeRaw([0xAB, 0x00, 0x13, enable ? 0x01 : 0x00]);
  }

  Future<void> triggerHeartRate() async {
    await writeRaw([0xAB, 0x00, 0x82, 0x01]);
  }

  Future<bool> writeRaw(List<int> bytes) async {
    if (dogpWriteChar == null) return false;
    try {
      await dogpWriteChar!.write(
        bytes,
        withoutResponse: dogpWriteChar!.properties.writeWithoutResponse,
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
    dogpWriteChar = null;
    dogpNotifyChar = null;
    alertChar = null;
    batteryChar = null;
    log("Disconnected");
  }
}
