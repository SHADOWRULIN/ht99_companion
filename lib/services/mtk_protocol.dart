import 'dart:convert';

class MtkProtocol {
  static const List<int> magic = [0xF0, 0xF0, 0xF0, 0xF1];

  // Wraps command tags and payloads in the MTK 0xF0F0F0F1 binary frame
  static List<int> packFrame(String tag, List<int> payload) {
    List<int> tagBytes = utf8.encode(tag);
    List<int> body = [...tagBytes, ...payload];
    int len = body.length;

    return [
      ...magic,
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
      ...body,
    ];
  }

  // 1. Initial Handshake Request (Prevents watch disconnects)
  static List<int> buildReconciliationRequest() {
    return packFrame("SYNC ", utf8.encode("REQV"));
  }

  // 2. Time Synchronization (12h vs 24h toggle)
  static List<int> buildSyncTime(bool is12Hour) {
    int nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int tzOffsetMillis = DateTime.now().timeZoneOffset.inMilliseconds;
    String mode = is12Hour ? "0" : "1";
    String payload = "$nowSeconds $tzOffsetMillis $mode";
    return packFrame("SYNC ", utf8.encode(payload));
  }

  // 3. Pedometer & Daily Stats Request (GET,0)
  static List<int> buildPedometerQuery() {
    return packFrame(
        "EXCD ", utf8.encode("KCT_PEDOMETER kct_pedometer 0 0 5 GET,0"));
  }

  // 4. Device Hardware & Battery Query (GET,10)
  static List<int> buildDeviceQuery() {
    return packFrame("EXCD ", utf8.encode("WW ww 0 0 6 GET,10"));
  }

  // 5. XML Push Notification
  static List<int> buildNotificationXml(
      int msgId, String title, String content, String sender) {
    int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String xml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<event_report>'
        '<header>'
        '<category>notification</category>'
        '<subType>text</subType>'
        '<msgId>$msgId</msgId>'
        '<action>add</action>'
        '</header>'
        '<body>'
        '<title>$title</title>'
        '<content>$content</content>'
        '<sender>$sender</sender>'
        '<timestamp>$timestamp</timestamp>'
        '</body>'
        '</event_report>';
    return packFrame("DATA ", utf8.encode(xml));
  }

  // 6. Weather Forecast Payload
  static List<int> buildWeather(
      String city, String condition, int temp, int high, int low) {
    String payload = "$city $condition $temp $high $low";
    return packFrame("EXCD ",
        utf8.encode("smartwatch yahooweather 0 0 ${payload.length} $payload"));
  }
}
