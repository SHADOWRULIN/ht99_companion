import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_model.dart';
import 'mtk_protocol.dart';

class WatchBleService {
  static const MethodChannel _ctsChannel =
      MethodChannel("com.ht99.companion/cts");
  static const MethodChannel _phoneChannel =
      MethodChannel("com.ht99.companion/phone");
  static const MethodChannel _notifChannel =
      MethodChannel("com.ht99.companion/notifications");

  BluetoothDevice? device;
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  BluetoothCharacteristic? alertChar;
  BluetoothCharacteristic? batteryChar;

  StreamSubscription? _scanSub;
  final List<StreamSubscription> _notifySubs = [];

  final TelemetryModel telemetry = TelemetryModel();
  final List<String> logs = [];

  bool isConnecting = false;
  bool isConnected = false;
  bool isPhoneRinging = false;

  final Set<String> enabledPackages = {
    "com.whatsapp",
    "com.facebook.katana",
    "com.instagram.android",
    "com.twitter.android",
    "com.google.android.apps.messaging",
  };

  void Function(String)? onStatus;
  void Function()? onData;
  void Function()? onConnected;
  void Function()? onFindPhoneTriggered;

  WatchBleService() {
    _notifChannel.setMethodCallHandler((call) async {
      if (call.method == "onNotificationReceived") {
        final Map args = call.arguments as Map;
        final String pkg = args["package"] ?? "";
        final String title = args["title"] ?? "";
        final String body = args["body"] ?? "";

        if (enabledPackages.contains(pkg) && isConnected) {
          pushNotification(title, body);
        }
      }
    });
  }

  void log(String msg) {
    String ts = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, "[$ts] $msg");
    if (logs.length > 200) logs.removeLast();
    onData?.call();
  }

  Future<void> scanAndConnect() async {
    if (isConnecting || isConnected) return;
    isConnecting = true;

    try {
      await _ctsChannel.invokeMethod("startCtsServer");
    } catch (_) {}

    onStatus?.call("Scanning for HT99...");
    log("Scanning for HT99...");

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      log("Scan error: $e");
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
          license: License.nonprofit, autoConnect: false, mtu: 256);
      device = target;
      isConnected = true;
      isConnecting = false;
      log("Connected. Discovering services...");

      List<BluetoothService> services = await target.discoverServices();

      for (var s in services) {
        for (var c in s.characteristics) {
          String u = c.uuid.str.toLowerCase();

          if (u.contains("2aa1")) {
            writeChar = c;
          }
          if (u.contains("2aa0") || u.contains("2abc")) {
            notifyChar = c;
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

      // Transmit WWfit initialization sequence
      for (var frame in MtkProtocol.buildWwfitHandshake()) {
        await writeRaw(frame);
        await Future.delayed(const Duration(milliseconds: 40));
      }

      await writeRaw(MtkProtocol.queryKctPedometer());
      await autoSyncTime12Hour();
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
    String text = String.fromCharCodes(data.where((b) => b >= 32 && b <= 126));

    log("RX [$uuid]: $text ($hex)");

    // Watch triggers "Find Phone"
    if (text.contains("10,4,1")) {
      log("WATCH TRIGGERED FIND PHONE!");
      triggerFindPhoneAlarm();
      return;
    }
    if (text.contains("10,4,0")) {
      log("Watch cancelled Find Phone.");
      stopFindPhoneAlarm();
      return;
    }

    // Parse WWfit telemetry strings
    if (text.contains("01,1") || text.contains("KCT_PEDOMETER")) {
      List<String> p = text.split(",");
      if (p.length >= 4) {
        telemetry.steps = int.tryParse(p[2]) ?? telemetry.steps;
        telemetry.calories =
            int.tryParse(p[3]) ?? (telemetry.steps * 0.04).round();
        telemetry.distanceKm = telemetry.steps * 0.00075;
        log("Steps synced: ${telemetry.steps}");
        onData?.call();
      }
    } else if (text.contains("03,1")) {
      List<String> p = text.split(",");
      if (p.length >= 3) {
        int bpm = int.tryParse(p[2]) ?? telemetry.heartRate;
        _recordHeartRate(bpm);
      }
    } else if (text.contains("04,1")) {
      List<String> p = text.split(",");
      if (p.length >= 4) {
        telemetry.systolicBp = int.tryParse(p[2]) ?? 120;
        telemetry.diastolicBp = int.tryParse(p[3]) ?? 80;
        log("BP synced: ${telemetry.systolicBp}/${telemetry.diastolicBp}");
        onData?.call();
      }
    } else if (text.contains("11,1")) {
      List<String> p = text.split(",");
      if (p.length >= 3) {
        telemetry.bodyTemp = double.tryParse(p[2]) ?? 36.5;
        log("Temp synced: ${telemetry.bodyTemp}°C");
        onData?.call();
      }
    }
  }

  void _recordHeartRate(int bpm) {
    if (bpm <= 30 || bpm >= 220) return;
    telemetry.heartRate = bpm;
    String timeStr = DateTime.now().toIso8601String().substring(11, 16);
    telemetry.hrHistory.insert(0, HeartRateRecord(bpm: bpm, time: timeStr));
    if (telemetry.hrHistory.length > 50) telemetry.hrHistory.removeLast();
    log("Heart Rate: $bpm BPM at $timeStr");
    onData?.call();
  }

  Future<void> measureHeartRateLive() async {
    await writeRaw(MtkProtocol.queryHeartRate());
    log("Dispatched live Heart Rate measure command");
  }

  void triggerFindPhoneAlarm() {
    isPhoneRinging = true;
    _phoneChannel.invokeMethod("startAlarm");
    onFindPhoneTriggered?.call();
    onData?.call();
  }

  void stopFindPhoneAlarm() {
    isPhoneRinging = false;
    _phoneChannel.invokeMethod("stopAlarm");
    writeRaw(MtkProtocol.stopFindPhone());
    onData?.call();
  }

  Future<void> autoSyncTime12Hour() async {
    try {
      await _ctsChannel.invokeMethod("broadcastCtsTime");
      await _ctsChannel.invokeMethod("setTimeFormat", {"is12Hour": true});
    } catch (_) {}

    await writeRaw(MtkProtocol.build12HourFormatCmd());
    log("Auto-synced time in 12-Hour format");
    onData?.call();
  }

  Future<void> queryAllHealthData() async {
    await writeRaw(MtkProtocol.querySteps());
    await Future.delayed(const Duration(milliseconds: 40));
    await writeRaw(MtkProtocol.queryKctPedometer());
    await Future.delayed(const Duration(milliseconds: 40));
    await writeRaw(MtkProtocol.queryHeartRate());
    await Future.delayed(const Duration(milliseconds: 40));
    await writeRaw(MtkProtocol.queryBloodPressure());
    await Future.delayed(const Duration(milliseconds: 40));
    await writeRaw(MtkProtocol.queryThermometer());
    await Future.delayed(const Duration(milliseconds: 40));
    await writeRaw(MtkProtocol.querySleep());
  }

  Future<void> readSigBattery() async {
    if (batteryChar != null) {
      try {
        var v = await batteryChar!.read();
        if (v.isNotEmpty) {
          telemetry.batteryLevel = v[0];
          log("SIG Battery: ${telemetry.batteryLevel}%");
          onData?.call();
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> saveAlarm(WatchAlarm alarm) async {
    int mask = 0;
    for (int i = 0; i < alarm.days.length; i++) {
      if (alarm.days[i]) mask |= (1 << i);
    }
    await writeRaw(MtkProtocol.buildSetAlarmPacket(
        alarm.hour, alarm.minute, mask, alarm.isEnabled));
    if (!telemetry.alarms.contains(alarm)) {
      telemetry.alarms.add(alarm);
    }
    log("Alarm saved: ${alarm.hour}:${alarm.minute.toString().padLeft(2, '0')}");
    onData?.call();
  }

  Future<void> setDrinkWaterReminder(bool enabled, int interval) async {
    telemetry.isDrinkWaterEnabled = enabled;
    telemetry.drinkWaterIntervalMinutes = interval;
    await writeRaw(MtkProtocol.buildDrinkWaterPacket(enabled, interval));
    log("Drink Water set: $enabled every $interval min");
    onData?.call();
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
    log("Pushed Notification: $title");
  }

  Future<void> pushWeather(
      int tempC, int conditionCode, int highC, int lowC) async {
    await writeRaw(
        MtkProtocol.buildWeatherPacket(tempC, conditionCode, highC, lowC));
    log("Dispatched Weather: $tempC°C");
  }

  Future<bool> writeRaw(List<int> bytes) async {
    if (writeChar == null || device == null) return false;
    const int chunkSize = 20;

    try {
      if (bytes.length <= chunkSize) {
        // Write with response matches g0.java write_type=2
        await writeChar!.write(bytes, withoutResponse: false);
        return true;
      }
      for (int i = 0; i < bytes.length; i += chunkSize) {
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        await writeChar!.write(bytes.sublist(i, end), withoutResponse: false);
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
