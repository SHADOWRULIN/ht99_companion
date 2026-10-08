import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_model.dart';
import 'mtk_protocol.dart';

class WatchBleService {
  static const MethodChannel _ctsChannel =
      MethodChannel("com.ht99.companion/cts");

  BluetoothDevice? device;
  BluetoothCharacteristic? dogpWriteChar; // 0x2AA1
  BluetoothCharacteristic? dogpNotifyChar; // 0x2AA0 / 0x2ABC
  BluetoothCharacteristic? alertChar; // 0x2A06
  BluetoothCharacteristic? batteryChar; // 0x2A19

  StreamSubscription? _scanSub;
  final List<StreamSubscription> _notifySubs = [];

  final TelemetryModel telemetry = TelemetryModel();
  final List<String> logs = [];

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
          onStatus?.call("Found HT99. Binding...");
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
    } catch (_) {}
  }

  Future<void> _bind(BluetoothDevice target) async {
    try {
      await target.connect(
          license: License.nonprofit, autoConnect: false, mtu: 256);
      device = target;
      log("Connected. Discovering services...");

      List<BluetoothService> services = await target.discoverServices();

      for (var s in services) {
        for (var c in s.characteristics) {
          String u = c.uuid.str.toLowerCase();

          if (u.contains("2aa1")) dogpWriteChar = c;
          if (u.contains("2aa0") || u.contains("2abc")) dogpNotifyChar = c;
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

      log("Endpoints acquired. Initializing MTK handshake...");
      onStatus?.call("Connected & Initialized");
      onConnected?.call();

      // Handshake: Send REQV immediately to prevent watch disconnection
      await writeRaw(MtkProtocol.buildReconciliationRequest());
      await Future.delayed(const Duration(milliseconds: 150));

      // Synchronize clock and query hardware stats
      await syncClock(telemetry.is12Hour);
      await queryPedometer();
      await readSigBattery();
    } catch (e) {
      log("Bind error: $e");
      onStatus?.call("Bind failed");
    }
  }

  void _parseIncoming(String uuid, List<int> data) {
    if (data.isEmpty) return;
    String hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    log("RX [$uuid]: $hex");

    String text = String.fromCharCodes(data.where((b) => b >= 32 && b <= 126));

    // Watch queries iOS/CTS verification
    if (text.contains("ios indication")) {
      log("Watch requested CTS link verification.");
      syncClock(telemetry.is12Hour);
      return;
    }

    // Pedometer response stream
    if (text.contains("MTK_PEDOMETER") || text.contains("kct_pedometer")) {
      List<String> parts = text.split(" ");
      if (parts.length >= 4) {
        telemetry.steps = int.tryParse(parts[1]) ?? telemetry.steps;
        telemetry.calories = int.tryParse(parts[2]) ?? telemetry.calories;
        int meters =
            int.tryParse(parts[3]) ?? (telemetry.distanceKm * 1000).toInt();
        telemetry.distanceKm = meters / 1000.0;
        log("Parsed Pedometer: ${telemetry.steps} steps, ${telemetry.calories} kcal");
        onData?.call();
      }
    }
  }

  Future<void> syncClock(bool is12Hour) async {
    telemetry.is12Hour = is12Hour;
    try {
      await _ctsChannel.invokeMethod("broadcastCtsTime");
    } catch (_) {}

    await writeRaw(MtkProtocol.buildSyncTime(is12Hour));
    log("Dispatched Time Sync (12h=$is12Hour)");
    onData?.call();
  }

  Future<void> queryPedometer() async {
    await writeRaw(MtkProtocol.buildPedometerQuery());
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
    await writeRaw(MtkProtocol.buildDeviceQuery());
  }

  Future<void> ringWatch() async {
    if (alertChar != null) {
      try {
        await alertChar!.write([0x02], withoutResponse: true);
        log("Dispatched High Alert (0x02)");
      } catch (_) {}
    }
  }

  Future<void> pushNotification(String title, String body) async {
    await writeRaw(
        MtkProtocol.buildNotificationXml(1, title, body, "Companion"));
    log("Dispatched Notification: $title");
  }

  Future<void> pushWeather(
      String city, String condition, int temp, int high, int low) async {
    await writeRaw(MtkProtocol.buildWeather(city, condition, temp, high, low));
    log("Dispatched Weather: $city $temp°C");
  }

  Future<bool> writeRaw(List<int> bytes) async {
    if (dogpWriteChar == null) return false;
    const int chunkSize = 20;

    try {
      for (int i = 0; i < bytes.length; i += chunkSize) {
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        List<int> chunk = bytes.sublist(i, end);

        // Uses write with response falling back to withoutResponse based on descriptors
        await dogpWriteChar!.write(
          chunk,
          withoutResponse: dogpWriteChar!.properties.writeWithoutResponse,
        );
        await Future.delayed(const Duration(milliseconds: 14));
      }
      return true;
    } catch (e) {
      log("Write raw exception: $e");
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
    dogpWriteChar = null;
    dogpNotifyChar = null;
    alertChar = null;
    batteryChar = null;
    log("Watch disconnected");
    onStatus?.call("Disconnected");
  }
}
