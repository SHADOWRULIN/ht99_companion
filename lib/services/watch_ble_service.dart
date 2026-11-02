import 'dart:async';
import 'package:flutter/services.dart';
import '../models/telemetry_model.dart';
import 'mtk_protocol.dart';

class WatchBleService {
  static const MethodChannel _engine = MethodChannel("ht99/engine");
  static const EventChannel _events = EventChannel("ht99/events");
  static const MethodChannel _ctsChannel =
      MethodChannel("com.ht99.companion/cts");
  static const MethodChannel _phoneChannel =
      MethodChannel("com.ht99.companion/phone");
  static const MethodChannel _notifChannel =
      MethodChannel("com.ht99.companion/notifications");

  StreamSubscription? _eventSub;

  final TelemetryModel telemetry = TelemetryModel();
  final List<String> logs = [];

  bool isConnecting = false;
  bool isConnected = false;
  bool isPhoneRinging = false;

  // User Profile & Sync Settings State
  bool is24Hour = false;
  int stepGoal = 10000;
  int heightCm = 170;
  int weightKg = 65;
  bool male = true;

  // Compatibility getter for legacy UI checks
  Object? get writeChar => isConnected ? true : null;

  final Set<String> enabledPackages = {
    "com.whatsapp",
    "com.facebook.katana",
    "com.instagram.android",
    "com.twitter.android",
    "com.google.android.apps.messaging",
    "com.android.server.telecom",
    "com.google.android.gm",
  };

  void Function(String)? onStatus;
  void Function()? onData;
  void Function()? onConnected;
  void Function()? onFindPhoneTriggered;

  WatchBleService() {
    _eventSub =
        _events.receiveBroadcastStream().listen(_onNativeEvent, onError: (e) {
      log("Event stream error: $e");
    });

    _notifChannel.setMethodCallHandler((call) async {
      if (call.method == "onNotificationReceived") {
        final Map args = call.arguments as Map;
        final String pkg = args["package"] ?? "";
        final String title = args["title"] ?? "";
        final String body = args["body"] ?? "";
        log("Notif [$pkg]: $title - $body");
      }
    });

    syncAllowedPackages();
  }

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final String type = raw["type"]?.toString() ?? "";

    switch (type) {
      case "log":
        final String msg = raw["message"]?.toString() ?? "";
        if (msg.isNotEmpty) log(msg);
        break;

      case "state":
        final bool prevConnected = isConnected;
        isConnected = raw["connected"] == true;
        isConnecting = raw["connecting"] == true;
        final String status = raw["status"]?.toString() ?? "";
        if (status.isNotEmpty) {
          onStatus?.call(status);
        }
        if (!prevConnected && isConnected) {
          onConnected?.call();
        }
        onData?.call();
        break;

      case "telemetry":
        if (raw["battery"] is int) {
          telemetry.batteryLevel = raw["battery"] as int;
        }
        if (raw["steps"] is int) {
          telemetry.steps = raw["steps"] as int;
        }
        if (raw["calories"] is int) {
          telemetry.calories = raw["calories"] as int;
        }
        if (raw["distanceKm"] is num) {
          telemetry.distanceKm = (raw["distanceKm"] as num).toDouble();
        }
        if (raw["heartRate"] is int) {
          _recordHeartRate(raw["heartRate"] as int);
        }
        if (raw["systolicBp"] is int) {
          telemetry.systolicBp = raw["systolicBp"] as int;
        }
        if (raw["diastolicBp"] is int) {
          telemetry.diastolicBp = raw["diastolicBp"] as int;
        }
        if (raw["bodyTemp"] is num) {
          telemetry.bodyTemp = (raw["bodyTemp"] as num).toDouble();
        }
        if (raw["immunity"] is int) {
          telemetry.immunity = raw["immunity"] as int;
        }
        if (raw["sleepHours"] is num) {
          telemetry.sleepHours = (raw["sleepHours"] as num).toDouble();
        }
        onData?.call();
        break;

      case "findPhone":
        final bool ringing = raw["ringing"] == true;
        isPhoneRinging = ringing;
        if (ringing) {
          onFindPhoneTriggered?.call();
        }
        onData?.call();
        break;
    }
  }

  void _recordHeartRate(int bpm) {
    if (bpm <= 30 || bpm >= 220) return;
    telemetry.heartRate = bpm;
    String timeStr = DateTime.now().toIso8601String().substring(11, 16);
    telemetry.hrHistory.insert(0, HeartRateRecord(bpm: bpm, time: timeStr));
    if (telemetry.hrHistory.length > 50) telemetry.hrHistory.removeLast();
  }

  void log(String msg) {
    String ts = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, "[$ts] $msg");
    if (logs.length > 250) logs.removeLast();
    onData?.call();
  }

  Future<void> syncAllowedPackages() async {
    try {
      await _engine.invokeMethod("setAllowedPackages", {
        "pkgs": enabledPackages.toList(),
      });
    } catch (_) {}
  }

  Future<void> scanAndConnect() async {
    if (isConnecting || isConnected) return;
    isConnecting = true;
    onData?.call();

    try {
      await _engine.invokeMethod("requestPermissions");
    } catch (_) {}

    try {
      await _ctsChannel.invokeMethod("startCtsServer");
    } catch (_) {}

    try {
      await _engine.invokeMethod("scanAndConnect");
    } catch (e) {
      log("Scan invoke error: $e");
      isConnecting = false;
      onData?.call();
    }
  }

  Future<void> stopScan() async {
    try {
      await _engine.invokeMethod("stopScan");
    } catch (_) {}
    isConnecting = false;
    onData?.call();
  }

  Future<void> disconnect({bool forget = false}) async {
    try {
      await _engine.invokeMethod("disconnect", {"forget": forget});
    } catch (_) {}
    isConnected = false;
    isConnecting = false;
    onData?.call();
  }

  Future<bool> sendWw(String cmd) async {
    try {
      final bool? ok = await _engine.invokeMethod<bool>("ww", {"cmd": cmd});
      return ok ?? false;
    } catch (e) {
      log("sendWw error: $e");
      return false;
    }
  }

  Future<void> measureHeartRateLive() async {
    await sendWw(MtkProtocol.liveHeartRate());
    log("Dispatched live Heart Rate command (05,1)");
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
    sendWw(MtkProtocol.stopFindPhone());
    onData?.call();
  }

  Future<void> autoSyncTime12Hour() async {
    await setTimeFormat(is24h: false);
  }

  Future<void> syncTime({bool? use24Hour}) async {
    if (use24Hour != null) {
      is24Hour = use24Hour;
      telemetry.is12Hour = !use24Hour;
    }
    try {
      await _ctsChannel.invokeMethod("broadcastCtsTime");
      await _ctsChannel.invokeMethod("setTimeFormat", {"is12Hour": !is24Hour});
      await _engine.invokeMethod("syncTime", {"is24Hour": is24Hour});
    } catch (_) {}
    onData?.call();
  }

  Future<void> setTimeFormat({required bool is24h}) async {
    is24Hour = is24h;
    telemetry.is12Hour = !is24h;
    await syncTime(use24Hour: is24h);
  }

  Future<void> queryAllHealthData() async {
    await readSigBattery();
    for (final q in MtkProtocol.allQueries) {
      await sendWw(q);
      await Future.delayed(const Duration(milliseconds: 120));
    }
    try {
      await _engine.invokeMethod("pedometer", {"cmd": "GET,0"});
    } catch (_) {}
  }

  Future<void> readSigBattery() async {
    try {
      await _engine.invokeMethod("readBattery");
    } catch (_) {}
  }

  Future<void> saveAlarm(WatchAlarm alarm) async {
    if (!telemetry.alarms.contains(alarm)) {
      telemetry.alarms.add(alarm);
    }
    final cmd = MtkProtocol.alarmsSet(telemetry.alarms);
    await sendWw(cmd);
    log("Alarms synced (${telemetry.alarms.length} total)");
    onData?.call();
  }

  Future<void> setDrinkWaterReminder(bool enabled, int interval) async {
    telemetry.isDrinkWaterEnabled = enabled;
    telemetry.drinkWaterIntervalMinutes = interval;
    final cmd = MtkProtocol.drinkWaterSet(
      enabled: enabled,
      intervalMinutes: interval,
    );
    await sendWw(cmd);
    log("Drink Water reminder synced: $enabled (${interval}m)");
    onData?.call();
  }

  Future<void> setSedentaryReminder({
    required bool enabled,
    int intervalMinutes = 60,
    int startHour = 9,
    int endHour = 21,
  }) async {
    final cmd = MtkProtocol.sedentarySet(
      enabled: enabled,
      intervalMinutes: intervalMinutes,
      startHour: startHour,
      endHour: endHour,
    );
    await sendWw(cmd);
    log("Sedentary reminder synced: $enabled (${intervalMinutes}m)");
  }

  Future<void> syncUserInfo({
    int? goal,
    int? height,
    int? weight,
    bool? isMale,
  }) async {
    if (goal != null) stepGoal = goal;
    if (height != null) heightCm = height;
    if (weight != null) weightKg = weight;
    if (isMale != null) male = isMale;

    final cmd = MtkProtocol.userInfoSet(
      stepGoal: stepGoal,
      heightCm: heightCm,
      weightKg: weightKg,
      male: male,
    );
    await sendWw(cmd);
    log("User profile synced: goal=$stepGoal, ${heightCm}cm, ${weightKg}kg");
    onData?.call();
  }

  Future<void> ringWatch() async {
    try {
      await _engine.invokeMethod("immediateAlert", {"level": 2});
    } catch (_) {}
  }

  Future<void> pushNotification(String title, String body,
      {String pkg = "com.whatsapp"}) async {
    try {
      await _engine.invokeMethod("notify", {
        "pkg": pkg,
        "title": title,
        "body": body,
        "isCall": false,
      });
    } catch (_) {}
  }

  Future<void> pushWeather(
    int tempC,
    int conditionCode,
    int highC,
    int lowC, {
    String city = "Karachi",
  }) async {
    try {
      await _engine.invokeMethod("weather", {
        "city": city,
        "conditionCode": conditionCode,
        "tempC": tempC,
        "highC": highC,
        "lowC": lowC,
      });
    } catch (_) {}
  }

  Future<bool> writeRaw(List<int> bytes) async {
    try {
      final bool? ok = await _engine.invokeMethod<bool>(
        "raw",
        {"bytes": Uint8List.fromList(bytes)},
      );
      return ok ?? false;
    } catch (e) {
      log("writeRaw error: $e");
      return false;
    }
  }

  void dispose() {
    _eventSub?.cancel();
  }
}
