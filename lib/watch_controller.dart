import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WatchController {
  static const String targetMac = "F9:47:B2:F6:EC:7C";

  // Discovered KCT Vendor UUIDs (from s1.g)
  static final List<String> kctWriteUuids = [
    "c3e6fea1-e966-1000-8000-be99c223df6a",
    "0783b03e-8535-b5a0-7140-a304d2495cba",
    "0000fee7-0000-1000-8000-00805f9b34fb",
    "0000fea1-0000-1000-8000-00805f9b34fb",
  ];

  static final List<String> kctNotifyUuids = [
    "c3e6fea2-e966-1000-8000-be99c223df6a",
    "0783b03e-8535-b5a0-7140-a304d2495cb8",
    "0000fee8-0000-1000-8000-00805f9b34fb",
  ];

  BluetoothDevice? device;
  BluetoothCharacteristic? kctWriteChar;
  BluetoothCharacteristic? kctNotifyChar;
  BluetoothCharacteristic? alertChar; // 0x2A06 (Find watch)
  BluetoothCharacteristic? batteryChar; // 0x2A19 (Direct battery read)

  StreamSubscription? _scanSub;
  StreamSubscription? _notifySub;

  int batteryLevel = 0;
  int stepCount = 0;
  int heartRate = 0;
  final List<String> logs = [];
  final List<Map<String, dynamic>> discoveredTree = [];

  void log(String msg) {
    String timestamp = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, "[$timestamp] $msg");
    if (logs.length > 60) logs.removeLast();
  }

  Future<void> connect({
    required Function(String) onStatus,
    required Function() onConnected,
    required Function() onData,
  }) async {
    onStatus("Scanning for HT99...");
    log("Started scan for $targetMac");

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      onStatus("Scan error: $e");
      log("Scan exception: $e");
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String mac = r.device.remoteId.str.toUpperCase();
        String name = r.device.platformName;

        if (mac == targetMac || name.contains("HT99")) {
          onStatus("Found HT99 ($mac). Connecting...");
          log("Target acquired: $name [$mac]");
          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();

          await _bind(r.device, onStatus, onConnected, onData);
          break;
        }
      }
    });
  }

  Future<void> _bind(
    BluetoothDevice targetDevice,
    Function(String) onStatus,
    Function() onConnected,
    Function() onData,
  ) async {
    try {
      await targetDevice.connect(
        license: License.free,
        autoConnect: false,
        mtu: 256,
      );
      device = targetDevice;
      log("GATT connected, discovering services...");
      onStatus("Discovering services...");

      List<BluetoothService> services = await targetDevice.discoverServices();
      discoveredTree.clear();

      for (var s in services) {
        String sUuid = s.uuid.str.toLowerCase();
        List<String> charUuids = [];

        for (var c in s.characteristics) {
          String cUuid = c.uuid.str.toLowerCase();
          charUuids.add(cUuid);

          // 1. Identify KCT Data Pipe
          if (kctWriteUuids.contains(cUuid)) {
            kctWriteChar = c;
            log("Bound KCT Write: $cUuid");
          }
          if (kctNotifyUuids.contains(cUuid) || c.properties.notify) {
            kctNotifyChar = c;
            log("Bound KCT Notify: $cUuid");
          }

          // 2. Identify Standard SIG Alert Level (0x2A06)
          if (cUuid.contains("2a06")) {
            alertChar = c;
            log("Bound Immediate Alert: $cUuid");
          }

          // 3. Identify Standard SIG Battery Level (0x2A19)
          if (cUuid.contains("2a19")) {
            batteryChar = c;
            log("Bound Battery Level: $cUuid");
          }
        }

        discoveredTree.add({"service": sUuid, "chars": charUuids});
      }

      // Fallback: If no proprietary KCT UUID matched, select the best writable vendor characteristic
      if (kctWriteChar == null) {
        for (var s in services) {
          for (var c in s.characteristics) {
            String cUuid = c.uuid.str.toLowerCase();
            if (!cUuid.contains("2a06") &&
                (c.properties.writeWithoutResponse || c.properties.write)) {
              kctWriteChar = c;
              log("Fallback selected write char: $cUuid");
              break;
            }
          }
          if (kctWriteChar != null) break;
        }
      }

      // Enable RX Notifications
      if (kctNotifyChar != null) {
        try {
          await kctNotifyChar!.setNotifyValue(true);
          _notifySub = kctNotifyChar!.lastValueStream.listen((data) {
            _parseIncoming(data, onData);
          });
          log("RX stream subscribed");
        } catch (e) {
          log("Notification subscription error: $e");
        }
      }

      String writeTag = kctWriteChar != null
          ? kctWriteChar!.uuid.str.substring(
              0,
              kctWriteChar!.uuid.str.length > 8
                  ? 8
                  : kctWriteChar!.uuid.str.length)
          : "None";
      onStatus("Connected! Pipe: [$writeTag]");
      onConnected();

      // Read direct battery & push initial time
      await Future.delayed(const Duration(milliseconds: 300));
      await readDirectBattery(onData);
      await syncTime();
    } catch (e) {
      onStatus("Binding error: $e");
      log("Binding error: $e");
    }
  }

  void _parseIncoming(List<int> data, Function() onData) {
    if (data.isEmpty) return;
    String hexStr =
        data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    log("RX: $hexStr");

    // Standard KCT packet parser
    if (data[0] == 0xAB && data.length >= 4) {
      int cmd = data[2];
      if (cmd == 0x91 || cmd == 0x08) {
        batteryLevel = data[3].clamp(0, 100);
        log("Telemetry: Battery = $batteryLevel%");
        onData();
      } else if (cmd == 0x51 && data.length >= 7) {
        stepCount = (data[4] << 16) | (data[5] << 8) | data[6];
        log("Telemetry: Steps = $stepCount");
        onData();
      } else if (cmd == 0x82 && data.length >= 4) {
        heartRate = data[3];
        log("Telemetry: HeartRate = $heartRate BPM");
        onData();
      }
    }
  }

  // Multi-Protocol Time Sync (sends KCT, MTK, and vendor formats)
  Future<void> syncTime() async {
    DateTime now = DateTime.now();

    // 1. KCT Command: 0xAB 0x00 0x04 [YearHi] [YearLo] [M] [D] [H] [M] [S]
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

    // 2. MTK2502 Command: 0xEA 0x01 0x01 [YY] [M] [D] [H] [M] [S]
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

    log("TX Time Sync (KCT): ${kctTime.map((e) => e.toRadixString(16)).join(' ')}");
    await writeRaw(kctTime);
    await Future.delayed(const Duration(milliseconds: 50));
    await writeRaw(mtkTime);
  }

  // Multi-Protocol Ring / Find Watch
  Future<void> ringWatch() async {
    // Method 1: Standard SIG Alert Level 0x2A06 (High Alert = 0x02)
    if (alertChar != null) {
      try {
        await alertChar!.write([0x02], withoutResponse: true);
        log("TX 0x2A06 High Alert (0x02) sent");
      } catch (e) {
        log("0x2A06 write error: $e");
      }
    }

    // Method 2: KCT Vendor Find Watch command
    List<int> kctFind = [0xAB, 0x00, 0x03, 0x01];
    log("TX KCT Find Watch (0xAB 0x00 0x03 0x01)");
    await writeRaw(kctFind);
  }

  // Read Battery directly from SIG service or query via KCT
  Future<void> readDirectBattery(Function() onData) async {
    if (batteryChar != null) {
      try {
        var val = await batteryChar!.read();
        if (val.isNotEmpty) {
          batteryLevel = val[0];
          log("Direct SIG Battery read: $batteryLevel%");
          onData();
          return;
        }
      } catch (e) {
        log("Direct battery read failed: $e");
      }
    }
    // Fallback: Send KCT Battery Query
    await writeRaw([0xAB, 0x00, 0x91]);
    await Future.delayed(const Duration(milliseconds: 50));
    await writeRaw([0xAB, 0x00, 0x51]); // Step Query
  }

  // Send Push Notification Text to HT99 Screen
  Future<void> pushNotification(String title, String body) async {
    List<int> titleBytes = title.codeUnits;
    List<int> bodyBytes = body.codeUnits;

    // MTK/KCT notification frame: 0xAB 0x00 0x02 [Type] [TitleLen] ... [Body]
    List<int> packet = [
      0xAB,
      0x00,
      0x02,
      0x01, // Notification Type (Generic/App)
      titleBytes.length,
      ...titleBytes,
      bodyBytes.length,
      ...bodyBytes,
    ];

    log("TX Push Notification: $title - $body");
    await writeRaw(packet);
  }

  Future<bool> writeRaw(List<int> bytes) async {
    if (kctWriteChar == null) {
      log("Cannot write: No write characteristic bound");
      return false;
    }

    const int chunk = 20;
    try {
      if (bytes.length <= chunk) {
        await kctWriteChar!.write(
          bytes,
          withoutResponse: kctWriteChar!.properties.writeWithoutResponse,
        );
        return true;
      }

      for (int i = 0; i < bytes.length; i += chunk) {
        int end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
        await kctWriteChar!.write(
          bytes.sublist(i, end),
          withoutResponse: kctWriteChar!.properties.writeWithoutResponse,
        );
        await Future.delayed(const Duration(milliseconds: 20));
      }
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
    kctWriteChar = null;
    kctNotifyChar = null;
    alertChar = null;
    batteryChar = null;
    log("Disconnected from watch");
  }
}
