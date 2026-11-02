import 'dart:convert';
import '../models/telemetry_model.dart';

/// Command builders for the WWfit "WW" command channel (EXCD frames).
/// RC4 encryption and 0xF0F0F0F1 framing happen natively in MtkCodec.kt.
class MtkProtocol {
  static String two(int v) => v.toString().padLeft(2, '0');

  // ---- Queries (Phone -> Watch) from c.java ----
  static const String deviceInfo = "01,1";
  static const String userInfo = "02,1";
  static const String steps = "03,1";
  static const String sleep = "04,1";
  static const String heartRate = "05,1";
  static const String alarms = "06,1";
  static const String sedentary = "07,1";
  static const String water = "08,1";
  static const String battery = "11,1";
  static const String bloodPressure = "13,1";
  static const String temperature = "14,1";
  static const String immunity = "15,1";

  static const List<String> allQueries = [
    deviceInfo,
    battery,
    steps,
    sleep,
    heartRate,
    bloodPressure,
    temperature,
    immunity,
    alarms,
    sedentary,
    water,
  ];

  // ---- Settings & Control Commands ----
  static String timeFormat(bool is24h) => is24h ? "SET,40,1" : "SET,40,0";
  static String stopFindPhone() => "10,4,0";
  static String findWatch() => "12,4,1";
  static String liveHeartRate() => "05,1";

  /// 02,2,target|height|weight|sex (from InformationSettingsActivity.java)
  static String userInfoSet({
    required int stepGoal,
    required int heightCm,
    required int weightKg,
    required bool male,
  }) {
    return "02,2,$stepGoal|$heightCm|$weightKg|${male ? 1 : 0}";
  }

  /// 06,2,count,HH:mm|repeatMask|0|0|enabled (from AlarmSettingsActivity.java)
  static String alarmsSet(List<WatchAlarm> list) {
    if (list.isEmpty) return "06,2,0";
    final buf = StringBuffer("${list.length}");
    for (final a in list) {
      final hhmm = "${two(a.hour)}:${two(a.minute)}";
      final en = a.isEnabled ? "1" : "0";
      buf.write(",$hhmm|${a.repeatMask}|0|0|$en");
    }
    return "06,2,${buf.toString()}";
  }

  /// 07,2,enable|startH|endH|intervalMin|repeatMask (from LongSitSettingsActivity.java)
  static String sedentarySet({
    required bool enabled,
    int startHour = 9,
    int endHour = 21,
    int intervalMinutes = 60,
    int repeatMask = 127,
  }) {
    return "07,2,${enabled ? 1 : 0}|$startHour|$endHour|$intervalMinutes|$repeatMask";
  }

  /// 08,2,HHmm|repeatMask|enabled (from DrinkingSettingsActivity.java)
  static String drinkWaterSet({
    required bool enabled,
    required int intervalMinutes,
    List<String> slots = const [
      "08:00",
      "09:00",
      "10:00",
      "11:00",
      "12:00",
      "14:00",
      "15:00",
      "16:00"
    ],
  }) {
    final buf = StringBuffer("08,2");
    final en = enabled ? "1" : "0";
    for (final s in slots) {
      final compact = s.replaceAll(":", "");
      buf.write(",$compact|127|$en");
    }
    return buf.toString();
  }

  // Legacy byte helpers for compatibility
  static List<int> buildWwCmd(String cmd) => utf8.encode(cmd);
}
