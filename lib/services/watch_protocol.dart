import 'dart:convert';
import 'dart:typed_data';

class WatchProtocol {
  // MediaTek Frame Magic: 0xF0F0F0F1
  static final Uint8List fsmHeader =
      Uint8List.fromList([0xF0, 0xF0, 0xF0, 0xF1]);

  // Packages XML notifications into MTK FSM frames
  static List<int> buildNotificationFrame(
      int msgId, String title, String body, String sender) {
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
        '<content>$body</content>'
        '<sender>$sender</sender>'
        '<timestamp>$timestamp</timestamp>'
        '</body>'
        '</event_report>';

    Uint8List xmlBytes = utf8.encode(xml);
    return wrapFsmFrame(xmlBytes);
  }

  // 12-Hour (0x00) vs 24-Hour (0x01) Command Payload
  static List<int> buildTimeFormatPayload(bool is12Hour) {
    return [is12Hour ? 0x00 : 0x01];
  }

  // Activation sequence for PDMS Step Counter
  static List<int> buildPdmsActivationPayload(int intervalSeconds) {
    int interval = intervalSeconds.clamp(1, 60);
    return [0x0A, 0x00, 0x01, 0x00, interval, 0x00];
  }

  // Handshake acknowledgment for MTK Wearable FSM
  static List<int> buildHandshakeAck() {
    String handshake = "mtk_bnapk bnsrv_time 0 0 0 ";
    return wrapFsmFrame(utf8.encode(handshake));
  }

  // Prepends 0xF0F0F0F1 + 4-byte Big-Endian Length
  static List<int> wrapFsmFrame(List<int> payload) {
    int len = payload.length;
    List<int> frame = [
      0xF0,
      0xF0,
      0xF0,
      0xF1,
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
      ...payload,
    ];
    return frame;
  }
}
