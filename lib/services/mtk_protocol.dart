import 'dart:convert';

class MtkProtocol {
  // 1. WWfit Handshake (Cancels 20s disconnect timer & turns watch icon BLUE)
  static List<List<int>> buildWwfitHandshake() {
    const commands = ["01,1", "03,1", "04,1", "05,1", "11,1"];
    return commands.map((cmd) => buildWwfitCmd(cmd)).toList();
  }

  // 2. WWfit Command Framer: "WW ww 0 0 <len> <cmd>"
  static List<int> buildWwfitCmd(String cmd) {
    String formatted = "WW ww 0 0 ${cmd.length} $cmd";
    return utf8.encode(formatted);
  }

  // 3. Proven KCT RTC Time Packet (Sets Watch Display Clock)
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

  // 4. 12-Hour vs 24-Hour Command (From c.M and c.N)
  // SET,40,0 = 12-Hour mode | SET,40,1 = 24-Hour mode
  static List<int> buildTimeFormatCmd(bool is12Hour) {
    return buildWwfitCmd(is12Hour ? "SET,40,0" : "SET,40,1");
  }

  // 5. Query Steps & Activity (PS,GET + KCT Step Request)
  static List<int> buildPedometerQuery() {
    return buildWwfitCmd("PS,GET");
  }

  static List<int> buildKctStepQuery() {
    return [0xAB, 0x00, 0x51];
  }

  // 6. Direct Hardware Battery Query
  static List<int> buildBatteryQuery() {
    return [0xAB, 0x00, 0x91];
  }

  // 7. Find Watch (Vibration Alert)
  static List<int> buildFindWatch() {
    return [0xAB, 0x00, 0x03, 0x01];
  }

  // 8. Notification Frame
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

  // 9. Weather Forecast Packet (Updates watch weather widget)
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
