import 'dart:convert';

class MtkProtocol {
  // 1. Initial Handshake Packets (Turns watch icon BLUE)
  static List<List<int>> buildWwfitHandshake() {
    const commands = ["01,1", "03,1", "04,1", "05,1", "11,1"];
    return commands.map((cmd) => buildWwfitCmd(cmd)).toList();
  }

  // 2. WWfit Command Framer: "WW ww 0 0 <len> <cmd>"
  static List<int> buildWwfitCmd(String cmd) {
    String formatted = "WW ww 0 0 ${cmd.length} $cmd";
    return utf8.encode(formatted);
  }

  // 3. Proven KCT RTC Time Packet
  static List<int> buildKctTimePacket(DateTime now) {
    return [
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
  }

  // 4. Force 12-Hour Mode (SET,40,0)
  static List<int> build12HourFormatCmd() => buildWwfitCmd("SET,40,0");

  // 5. Trigger Real-Time Heart Rate Measurement on Watch
  static List<int> triggerHeartRateMeasure() => [0xAB, 0x00, 0x82, 0x01];

  // 6. Query Health Sensors
  static List<int> querySteps() => buildWwfitCmd("01,1");
  static List<int> queryHeartRate() => buildWwfitCmd("03,1");
  static List<int> queryBloodPressure() => buildWwfitCmd("04,1");
  static List<int> queryImmunity() => buildWwfitCmd("05,1");
  static List<int> queryThermometer() => buildWwfitCmd("11,1");
  static List<int> querySleep() => buildWwfitCmd("02,1");

  // 7. Watch Alarm Setting
  static List<int> buildSetAlarmPacket(
      int hour, int minute, int repeatMask, bool enabled) {
    return [
      0xAB,
      0x00,
      0x07,
      hour & 0xFF,
      minute & 0xFF,
      repeatMask & 0xFF,
      enabled ? 0x01 : 0x00,
    ];
  }

  // 8. Drink Water Reminder Interval
  static List<int> buildDrinkWaterPacket(bool enabled, int intervalMinutes) {
    return [
      0xAB,
      0x00,
      0x12,
      enabled ? 0x01 : 0x00,
      intervalMinutes & 0xFF,
    ];
  }

  // 9. Stop Find Phone Acknowledgment
  static List<int> stopFindPhone() => buildWwfitCmd("10,4,0");

  // 10. Find Watch (Vibration Alert)
  static List<int> buildFindWatch() => [0xAB, 0x00, 0x03, 0x01];

  // 11. Notification Packet
  static List<int> buildNotificationPacket(String title, String body) {
    List<int> t = utf8.encode(title);
    List<int> b = utf8.encode(body);
    return [
      0xAB,
      0x00,
      0x02,
      0x01,
      t.length,
      ...t,
      b.length,
      ...b,
    ];
  }

  // 12. Weather Forecast Packet
  static List<int> buildWeatherPacket(
      int tempC, int conditionCode, int highC, int lowC) {
    return [
      0xAB,
      0x00,
      0x0E,
      tempC.clamp(-50, 100) & 0xFF,
      conditionCode & 0xFF,
      highC.clamp(-50, 100) & 0xFF,
      lowC.clamp(-50, 100) & 0xFF,
    ];
  }
}
