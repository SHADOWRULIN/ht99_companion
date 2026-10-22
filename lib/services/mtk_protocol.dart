import 'dart:convert';
import 'package:flutter/services.dart';

/// One MediaTek message is a native-encoded command frame, optionally followed
/// by a separate raw data segment. That split mirrors WWfit's queueing layer.
class MtkCommand {
  final int type;
  final String description;
  final List<int> frame;
  final List<int> data;

  const MtkCommand({
    required this.type,
    required this.description,
    required this.frame,
    this.data = const <int>[],
  });
}

class MtkProtocol {
  static const MethodChannel _channel = MethodChannel('com.ht99.companion/mtk');
  static bool _initialized = false;
  static String? lastInitializationError;
  static int _nextMessageId = 1;

  static Future<bool> initialize() async {
    if (_initialized) return true;

    lastInitializationError = null;

    try {
      final ok = await _channel.invokeMethod<bool>('initialize') ?? false;

      _initialized = ok;

      if (!ok) {
        lastInitializationError = 'Native initialization returned false.';
      }

      return ok;
    } on PlatformException catch (e) {
      lastInitializationError =
          '${e.code}: ${e.message}; details: ${e.details}';
      return false;
    } on MissingPluginException catch (e) {
      lastInitializationError = 'Missing native method channel: $e';
      return false;
    } catch (e) {
      lastInitializationError = e.toString();
      return false;
    }
  }

  /// Returns the exact byte frame produced by the WWfit APK's native encoder.
  /// Do not replace this with hand-built ASCII or guessed F0F0F0F1 frames.
  static Future<List<int>> encode(int type, String body) async {
    if (!await initialize()) {
      throw StateError('WWfit native Command library is not available.');
    }
    final dynamic result = await _channel.invokeMethod<dynamic>(
      'encodeCommand',
      <String, Object>{'type': type, 'body': body},
    );
    if (result is Uint8List) return result.toList(growable: false);
    if (result is List) {
      return result.map((dynamic v) => (v as num).toInt() & 0xff).toList();
    }
    throw StateError('Native command encoder returned an invalid result.');
  }

  static Future<Map<String, dynamic>> inspect(List<int> command) async {
    final dynamic result = await _channel.invokeMethod<dynamic>(
      'inspectCommand',
      <String, Object>{'bytes': Uint8List.fromList(command)},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{'type': -1, 'dataLength': 0, 'text': ''};
  }

  static Future<bool> validateDialMd5(List<int> bytes) async {
    try {
      return await _channel.invokeMethod<bool>(
            'validateDialMd5',
            <String, Object>{'bytes': Uint8List.fromList(bytes)},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static List<int> ascii(String value) => utf8.encode(value);

  /// WWfit's official EXCD helper sends the native command header first and
  /// the ASCII command body as a distinct data segment.
  static Future<MtkCommand> ww(String body) async {
    final data = ascii(body);
    final header = 'WW ww 0 0 ${data.length} ';
    return MtkCommand(
      type: 9,
      description: body,
      frame: await encode(9, header),
      data: data,
    );
  }

  static Future<MtkCommand> kctPedometer() async {
    const body = 'GET,0';
    final data = ascii(body);
    return MtkCommand(
      type: 9,
      description: 'KCT_PEDOMETER GET,0',
      frame: await encode(9, 'KCT_PEDOMETER kct_pedometer 0 0 ${data.length} '),
      data: data,
    );
  }

  static Future<MtkCommand> weather({
    required String city,
    required String condition,
    required int currentC,
    required int highC,
    required int lowC,
  }) async {
    // The original YahooWeather controller uses five space-separated fields.
    final safeCity = city.trim().replaceAll(RegExp(r'\s+'), '_');
    final safeCondition = condition.trim().replaceAll(RegExp(r'\s+'), '_');
    final body = '$safeCity $safeCondition $currentC $highC $lowC';
    final data = ascii(body);
    return MtkCommand(
      type: 9,
      description: 'weather $safeCity $safeCondition',
      frame: await encode(9, 'smartwatch yahooweather 0 0 ${data.length} '),
      data: data,
    );
  }

  static Future<MtkCommand> notification({
    required String title,
    required String body,
    required String appName,
    required String appId,
  }) async {
    final safeTitle =
        _xml(title.length > 128 ? '${title.substring(0, 128)}…' : title);
    final safeBody =
        _xml(body.length > 256 ? '${body.substring(0, 256)}…' : body);
    final safeApp = _xml(appName);
    final safeId = _xml(appId);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final msgId = _nextMessageId++;
    if (_nextMessageId > 65535) _nextMessageId = 1;
    final xml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<event_report><header><category>notification</category>'
        '<subType>text</subType><msgId>$msgId</msgId><action>add</action></header>'
        '<body><sender>$safeApp</sender><appId>$safeId</appId><timestamp>$now</timestamp>'
        '<title>$safeTitle</title><content>$safeBody</content></body></event_report>';
    final data = ascii(xml);
    // Native API builds "DATA <payload-byte-length>" for type 1.
    return MtkCommand(
      type: 1,
      description: 'notification: $title',
      frame: await encode(1, '${data.length}'),
      data: data,
    );
  }

  static Future<MtkCommand> syncTime({required int version}) async {
    final now = DateTime.now();
    final epochSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final zoneOffsetMs = now.timeZoneOffset.inMilliseconds;
    var payload = '$epochSeconds $zoneOffsetMs';
    if (version >= 340) payload += ' 1.1 ANDROID';
    return MtkCommand(
      type: 2,
      description: 'time sync (${now.toIso8601String()})',
      frame: await encode(2, payload),
    );
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
