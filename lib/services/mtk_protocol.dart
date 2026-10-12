import 'dart:convert';

class MtkProtocol {
  // WWfit Command Wrapper: "WW ww 0 0 <len> <cmd>"
  static List<int> buildWwCmd(String cmd) {
    String formatted = "WW ww 0 0 ${cmd.length} $cmd";
    return utf8.encode(formatted);
  }

  // Initial Handshake Sequence matching c.c()
  static List<List<int>> buildWwfitHandshake() {
    return [
      buildWwCmd("SET,40,0"), // 12-hour mode
      buildWwCmd("PS,GET"), // Pedometer status
      buildWwCmd("01,1"), // Step sync
      buildWwCmd("03,1"), // Heart rate sync
      buildWwCmd("04,1"), // Blood pressure sync
      buildWwCmd("11,1"), // Temperature sync
      buildWwCmd("05,1"), // Immunity sync
    ];
  }

  // Step Counter Query
  static List<int> querySteps() => buildWwCmd("01,1");
  static List<int> queryKctPedometer() =>
      utf8.encode("KCT_PEDOMETER kct_pedometer 0 0 5 GET,0");

  // Health Queries
  static List<int> queryHeartRate() => buildWwCmd("03,1");
  static List<int> queryBloodPressure() => buildWwCmd("04,1");
  static List<int> queryImmunity() => buildWwCmd("05,1");
  static List<int> queryThermometer() => buildWwCmd("11,1");
  static List<int> querySleep() => buildWwCmd("02,1");

  // Time format lock
  static List<int> build12HourFormatCmd() => buildWwCmd("SET,40,0");

  // Find Watch / Find Phone
  static List<int> buildFindWatch() => buildWwCmd("12,4,1");
  static List<int> stopFindPhone() => buildWwCmd("10,4,0");

  // Alarms
  static List<int> buildSetAlarmPacket(
      int hour, int minute, int repeatMask, bool enabled) {
    return buildWwCmd("SET,ALARM,$hour,$minute,$repeatMask,${enabled ? 1 : 0}");
  }

  // Water Reminder
  static List<int> buildDrinkWaterPacket(bool enabled, int intervalMinutes) {
    return buildWwCmd("SET,DRINK,${enabled ? 1 : 0},$intervalMinutes");
  }

  // Notification Packet
  static List<int> buildNotificationPacket(String title, String body) {
    int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String xml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<event_report>'
        '<header><category>notification</category><subType>text</subType><msgId>1</msgId><action>add</action></header>'
        '<body><title>$title</title><content>$body</content><sender>Companion</sender><timestamp>$timestamp</timestamp></body>'
        '</event_report>';
    return utf8.encode("DATA $xml");
  }

  // Weather Sync
  static List<int> buildWeatherPacket(
      int tempC, int conditionCode, int highC, int lowC) {
    String payload = "Karachi Sunny $tempC $highC $lowC";
    return utf8
        .encode("smartwatch yahooweather 0 0 ${payload.length} $payload");
  }
}
