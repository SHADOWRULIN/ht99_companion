import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/telemetry_model.dart';
import 'mtk_protocol.dart';

/// HT99 / WWfit companion transport.
///
/// Important design rules:
/// * The proprietary channel is initialized and framed by WWfit's own JNI
///   library. We never send hand-written ASCII where an encoded command is due.
/// * A successful GATT write means the phone's controller accepted the write;
///   it does NOT prove the watch applied a setting. Logs say that explicitly.
/// * Missing sensor values stay missing; we never invent a plausible-looking
///   heart rate, blood pressure, temperature, steps or oxygen value.
class WatchBleService {
  static const MethodChannel _ctsChannel = MethodChannel('com.ht99.companion/cts');
  static const MethodChannel _phoneChannel = MethodChannel('com.ht99.companion/phone');
  static const MethodChannel _notifChannel = MethodChannel('com.ht99.companion/notifications');

  static const String _dogpService = '000018a0-0000-1000-8000-00805f9b34fb';
  static const String _dogpWrite = '00002aa1-0000-1000-8000-00805f9b34fb';
  static const String _dogpRead = '00002aa0-0000-1000-8000-00805f9b34fb';
  static const String _dogpAltRead = '00002abc-0000-1000-8000-00805f9b34fb';
  static const String _alertUuid = '00002a06-0000-1000-8000-00805f9b34fb';
  static const String _batteryUuid = '00002a19-0000-1000-8000-00805f9b34fb';
  static const String _heartRateUuid = '00002a37-0000-1000-8000-00805f9b34fb';
  static const String _plxContinuousUuid = '00002a5f-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? device;
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  BluetoothCharacteristic? alertChar;
  BluetoothCharacteristic? batteryChar;
  BluetoothCharacteristic? heartRateChar;
  BluetoothCharacteristic? oxygenChar;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  final List<StreamSubscription<List<int>>> _notifySubs = [];
  final TelemetryModel telemetry = TelemetryModel();
  final List<String> logs = [];

  bool isConnecting = false;
  bool isConnected = false;
  bool isProtocolReady = false;
  bool isPhoneRinging = false;
  int? deviceVersion;
  DateTime? lastRealTelemetryAt;
  Completer<int>? _versionCompleter;
  bool _drainingRx = false;
  final List<int> _rxBuffer = <int>[];
  Map<String, dynamic>? _pendingRx;
  Future<void> _writeTail = Future<void>.value();

  final Set<String> enabledPackages = <String>{
    'com.whatsapp',
    'com.facebook.katana',
    'com.instagram.android',
    'com.twitter.android',
    'com.google.android.apps.messaging',
    'com.google.android.gm',
    'com.android.messaging',
  };

  void Function(String)? onStatus;
  void Function()? onData;
  void Function()? onConnected;
  void Function()? onFindPhoneTriggered;

  WatchBleService() {
    _notifChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'onNotificationReceived') return;
      final args = Map<dynamic, dynamic>.from(call.arguments as Map);
      final pkg = '${args['package'] ?? ''}';
      final title = '${args['title'] ?? ''}';
      final body = '${args['body'] ?? ''}';
      if (enabledPackages.contains(pkg) && isConnected) {
        await pushNotification(title, body, appId: pkg);
      }
    });
  }

  void log(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, '[$stamp] $message');
    if (logs.length > 300) logs.removeLast();
    onData?.call();
  }

  Future<void> scanAndConnect() async {
    if (isConnecting || isConnected) return;
    isConnecting = true;
    onStatus?.call('Preparing watch protocol…');
    log('Preparing native MediaTek command engine.');

    final nativeOk = await MtkProtocol.initialize();
    if (!nativeOk) {
      isConnecting = false;
      onStatus?.call('Native protocol unavailable');
      log('ERROR: libCommand.so could not initialize. See patch README and Android ABI settings.');
      return;
    }

    try {
      final server = await _ctsChannel.invokeMethod<bool>('startCtsServer') ?? false;
      log(server
          ? 'Phone Current Time + Time Format GATT profiles started.'
          : 'Warning: phone time-profile server/advertising did not start; time sync may be limited.');
    } catch (e) {
      log('Phone GATT server warning: $e');
    }

    onStatus?.call('Scanning for HT99…');
    log('Scanning for HT99 / MediaTek DOGP service.');
    final found = Completer<BluetoothDevice>();
    try {
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final name = result.device.platformName.toUpperCase();
          final services = result.advertisementData.serviceUuids
              .map((Guid id) => id.str.toLowerCase())
              .toList();
          final looksLikeTarget = name.contains('HT99') ||
              name.contains('WWFIT') ||
              services.any((id) => id.contains('18a0'));
          if (looksLikeTarget && !found.isCompleted) {
            found.complete(result.device);
          }
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      final target = await found.future.timeout(const Duration(seconds: 16));
      await stopScan();
      await _bind(target);
    } catch (e) {
      await stopScan();
      isConnecting = false;
      onStatus?.call('Watch not found');
      log('Scan failed or timed out: $e');
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await _scanSub?.cancel();
    } catch (_) {}
    _scanSub = null;
  }

  Future<void> _bind(BluetoothDevice target) async {
    try {
      onStatus?.call('Connecting…');
      log('Connecting to ${target.platformName.isEmpty ? 'HT99' : target.platformName} [${target.remoteId.str}].');
      await target.connect(license: License.nonprofit, autoConnect: false, mtu: 256);
      device = target;
      _connectionSub = target.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && isConnected) {
          unawaited(_handleRemoteDisconnect());
        }
      });

      onStatus?.call('Discovering services…');
      final services = await target.discoverServices();
      final available = <String>[];
      for (final service in services) {
        final su = service.uuid.str.toLowerCase();
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid.str.toLowerCase();
          if (uuid == _dogpWrite) writeChar = characteristic;
          if (uuid == _dogpRead || uuid == _dogpAltRead) {
            notifyChar ??= characteristic;
          }
          if (uuid == _alertUuid) alertChar = characteristic;
          if (uuid == _batteryUuid) batteryChar = characteristic;
          if (uuid == _heartRateUuid) heartRateChar = characteristic;
          if (uuid == _plxContinuousUuid) oxygenChar = characteristic;
        }
        if (su == _dogpService) available.add('DOGP');
      }

      if (writeChar == null) {
        throw StateError('The watch did not expose DOGP write characteristic 0x2AA1.');
      }
      if (notifyChar == null) {
        log('Warning: DOGP read/notify characteristic 0x2AA0 was not found.');
      }

      for (final service in services) {
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid.str.toLowerCase();
          final isTargetNotifier = uuid == _dogpRead ||
              uuid == _dogpAltRead ||
              uuid == _heartRateUuid ||
              uuid == _plxContinuousUuid;
          if (isTargetNotifier && (characteristic.properties.notify || characteristic.properties.indicate)) {
            try {
              await characteristic.setNotifyValue(true);
              _notifySubs.add(characteristic.lastValueStream.listen(
                (data) => _onCharacteristicValue(uuid, data),
                onError: (Object error) => log('Notify stream error [$uuid]: $error'),
              ));
            } catch (e) {
              log('Could not subscribe to $uuid: $e');
            }
          }
        }
      }

      isConnected = true;
      isConnecting = false;
      isProtocolReady = false;
      _rxBuffer.clear();
      _pendingRx = null;
      _versionCompleter = Completer<int>();
      onStatus?.call('Bluetooth connected · authenticating…');
      onConnected?.call();
      log('GATT link connected. Services: ${available.isEmpty ? 'standard/other' : available.join(', ')}.');
      log('Sending authentic MediaTek REQV handshake via native JNI (write-with-response).');
      final request = MtkCommand(
        type: 2,
        description: 'REQV handshake',
        frame: await MtkProtocol.encode(2, 'REQV'),
      );
      final writeOk = await _sendCommand(request);
      if (!writeOk) throw StateError('REQV write failed.');

      await readSigBattery();
      try {
        final version = await _versionCompleter!.future.timeout(const Duration(seconds: 8));
        log('Watch protocol version acknowledged: $version.');
      } on TimeoutException {
        log('No protocol version acknowledgement arrived. BLE is connected, but watch-control commands are not marked ready.');
      }
    } catch (e) {
      log('Connect/protocol error: $e');
      onStatus?.call('Connection failed');
      isConnected = false;
      isConnecting = false;
      isProtocolReady = false;
      try { await target.disconnect(); } catch (_) {}
      await _clearConnectionReferences();
    }
  }

  void _onCharacteristicValue(String uuid, List<int> bytes) {
    if (bytes.isEmpty) return;
    if (uuid == _heartRateUuid) {
      _parseStandardHeartRate(bytes);
      return;
    }
    if (uuid == _plxContinuousUuid) {
      _parseStandardOxygen(bytes);
      return;
    }

    final hex = bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final printable = String.fromCharCodes(bytes.where((int b) => b >= 32 && b <= 126));
    log('RX [$uuid]: ${printable.isEmpty ? '(binary)' : printable} [$hex]');
    if (printable.contains('10,4,1')) {
      triggerFindPhoneAlarm();
    } else if (printable.contains('10,4,0')) {
      stopFindPhoneAlarm();
    }

    if (uuid == _dogpRead || uuid == _dogpAltRead) {
      _rxBuffer.addAll(bytes);
      unawaited(_drainRxFrames());
      _parseStructuredTelemetry(printable);
    }
  }

  Future<void> _drainRxFrames() async {
    if (_drainingRx) return;
    _drainingRx = true;
    try {
      while (isConnected) {
        if (_pendingRx != null) {
          final needed = (_pendingRx!['dataLength'] as int?) ?? 0;
          if (needed <= 0) {
            final pending = _pendingRx!;
            _pendingRx = null;
            await _handleMtkMessage(
              (pending['type'] as int?) ?? -1,
              (pending['text'] as String?) ?? '',
              const <int>[],
            );
            continue;
          }
          if (_rxBuffer.length < needed) return;
          final body = _rxBuffer.sublist(0, needed);
          _rxBuffer.removeRange(0, needed);
          final pending = _pendingRx!;
          _pendingRx = null;
          await _handleMtkMessage(
            (pending['type'] as int?) ?? -1,
            (pending['text'] as String?) ?? '',
            body,
          );
          continue;
        }

        final magic = _findMagic(_rxBuffer);
        if (magic < 0) {
          // Retain only enough tail bytes to detect a split F0F0F0F1 marker.
          if (_rxBuffer.length > 3) _rxBuffer.removeRange(0, _rxBuffer.length - 3);
          return;
        }
        if (magic > 0) _rxBuffer.removeRange(0, magic);
        if (_rxBuffer.length < 8) return;
        final commandLength = ((_rxBuffer[4] & 0xff) << 24) |
            ((_rxBuffer[5] & 0xff) << 16) |
            ((_rxBuffer[6] & 0xff) << 8) |
            (_rxBuffer[7] & 0xff);
        if (commandLength <= 0 || commandLength > 1024 * 1024) {
          log('RX frame has invalid command length $commandLength; resynchronizing.');
          _rxBuffer.removeRange(0, 4);
          continue;
        }
        if (_rxBuffer.length < 8 + commandLength) return;
        final command = _rxBuffer.sublist(8, 8 + commandLength);
        _rxBuffer.removeRange(0, 8 + commandLength);
        try {
          final details = await MtkProtocol.inspect(command);
          var dataLength = (details['dataLength'] as num?)?.toInt() ?? 0;
          if (dataLength < 0 || dataLength > 1024 * 1024) dataLength = 0;
          _pendingRx = <String, dynamic>{
            'type': (details['type'] as num?)?.toInt() ?? -1,
            'dataLength': dataLength,
            'text': (details['text'] as String?) ?? '',
          };
        } catch (e) {
          log('Cannot inspect incoming MTK frame: $e');
          _pendingRx = <String, dynamic>{'type': -1, 'dataLength': 0, 'text': ''};
        }
      }
    } catch (e) {
      log('MTK receive parser error: $e');
    } finally {
      _drainingRx = false;
    }
  }

  int _findMagic(List<int> bytes) {
    for (var i = 0; i <= bytes.length - 4; i++) {
      if (bytes[i] == 0xf0 && bytes[i + 1] == 0xf0 && bytes[i + 2] == 0xf0 && bytes[i + 3] == 0xf1) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _handleMtkMessage(int type, String command, List<int> data) async {
    final body = utf8.decode(data, allowMalformed: true).replaceAll('\u0000', '').trim();
    log('MTK message type=$type command="${command.replaceAll('\n', ' ')}" dataBytes=${data.length}${body.isEmpty ? '' : ' data="$body"'}');

    // This is the same handshake/version state used by WWfit's ReadDataParser.
    if (type == 4) {
      final match = RegExp(r'\d{1,5}').firstMatch(body.isNotEmpty ? body : command);
      final version = match == null ? null : int.tryParse(match.group(0)!);
      if (version != null && version > 0) {
        deviceVersion = version;
        isProtocolReady = true;
        onStatus?.call('Connected · protocol v$version');
        if (_versionCompleter != null && !_versionCompleter!.isCompleted) {
          _versionCompleter!.complete(version);
        }
        await _syncNativeTime();
        await queryAllHealthData();
      }
      return;
    }
    if (type == 3) {
      log('Received MediaTek handshake message (type 3); waiting for version response before sending settings.');
      return;
    }

    _parseStructuredTelemetry(body);
    if (body.contains('10,4,1')) triggerFindPhoneAlarm();
    if (body.contains('10,4,0')) stopFindPhoneAlarm();
  }

  void _parseStructuredTelemetry(String text) {
    if (text.isEmpty) return;
    var changed = false;

    // These fields are updated only when the incoming body actually contains a
    // recognizable value. No fixed fallback values are assigned on parse failure.
    final stepMatch = RegExp(r'(?:^|[,;\s])01,1[,;\s]+(\d+)(?:[,;\s]+(\d+))?').firstMatch(text);
    if (stepMatch != null) {
      final steps = int.tryParse(stepMatch.group(1) ?? '');
      if (steps != null && steps >= 0 && steps < 200000) {
        telemetry.steps = steps;
        telemetry.hasStepData = true;
        final calories = int.tryParse(stepMatch.group(2) ?? '');
        if (calories != null && calories >= 0 && calories < 10000) {
          telemetry.calories = calories;
          telemetry.hasCaloriesData = true;
        }
        telemetry.distanceKm = steps * 0.00075; // Estimated from step count, not a sensor reading.
        changed = true;
        log('Step response parsed: $steps${telemetry.hasCaloriesData ? ' steps / ${telemetry.calories} kcal' : ' steps'}');
      }
    }

    final heartMatch = RegExp(r'(?:^|[,;\s])03,1[,;\s]+(\d{2,3})(?:$|[,;\s])').firstMatch(text);
    if (heartMatch != null) {
      final bpm = int.tryParse(heartMatch.group(1) ?? '');
      if (bpm != null) {
        _recordHeartRate(bpm);
        changed = true;
      }
    }

    final bpMatch = RegExp(r'(?:^|[,;\s])04,1[,;\s]+(\d{2,3})[,;\s]+(\d{2,3})(?:$|[,;\s])').firstMatch(text);
    if (bpMatch != null) {
      final sys = int.tryParse(bpMatch.group(1) ?? '');
      final dia = int.tryParse(bpMatch.group(2) ?? '');
      if (sys != null && dia != null && sys.inRange(50, 280) && dia.inRange(30, 180)) {
        telemetry.systolicBp = sys;
        telemetry.diastolicBp = dia;
        telemetry.hasBloodPressureData = true;
        changed = true;
        log('BP response parsed: $sys/$dia mmHg');
      }
    }

    final tempMatch = RegExp(r'(?:^|[,;\s])11,1[,;\s]+(-?\d{1,2}(?:\.\d+)?)').firstMatch(text);
    if (tempMatch != null) {
      final temperature = double.tryParse(tempMatch.group(1) ?? '');
      if (temperature != null && temperature >= 20 && temperature <= 50) {
        telemetry.bodyTemp = temperature;
        telemetry.hasTemperatureData = true;
        changed = true;
        log('Temperature response parsed: $temperature °C');
      }
    }

    final oxygenMatch = RegExp(r'(?:spo2|sp\s*o2|oxygen)[^0-9]{0,10}(\d{2,3})', caseSensitive: false).firstMatch(text);
    if (oxygenMatch != null) {
      final oxygen = int.tryParse(oxygenMatch.group(1) ?? '');
      if (oxygen != null && oxygen >= 50 && oxygen <= 100) {
        telemetry.bloodOxygen = oxygen;
        telemetry.hasBloodOxygenData = true;
        changed = true;
        log('Oxygen response parsed: $oxygen%');
      }
    }

    if (changed) {
      lastRealTelemetryAt = DateTime.now();
      onData?.call();
    }
  }


  void _recordHeartRate(int bpm) {
    if (bpm < 30 || bpm > 220) return;
    telemetry.heartRate = bpm;
    telemetry.hasHeartRateData = true;
    final time = DateTime.now().toIso8601String().substring(11, 16);
    if (telemetry.hrHistory.isEmpty || telemetry.hrHistory.first.bpm != bpm || telemetry.hrHistory.first.time != time) {
      telemetry.hrHistory.insert(0, HeartRateRecord(bpm: bpm, time: time));
      if (telemetry.hrHistory.length > 50) telemetry.hrHistory.removeLast();
    }
    lastRealTelemetryAt = DateTime.now();
    log('Heart rate measurement: $bpm BPM at $time');
    onData?.call();
  }

  void _parseStandardHeartRate(List<int> value) {
    if (value.length < 2) return;
    final flags = value[0];
    int bpm;
    if ((flags & 0x01) != 0) {
      if (value.length < 3) return;
      bpm = value[1] | (value[2] << 8);
    } else {
      bpm = value[1];
    }
    _recordHeartRate(bpm);
  }

  void _parseStandardOxygen(List<int> value) {
    // PLX continuous measurement begins with flags and then an IEEE-11073 SFLOAT
    // saturation. Only decode the fields when the standard-format packet is long
    // enough and reports a plausible percent value.
    if (value.length < 3) return;
    var offset = 1;
    final flags = value[0];
    if ((flags & 0x01) != 0) offset += 7; // timestamp present
    if ((flags & 0x02) != 0) offset += 2; // measurement status present
    if ((flags & 0x04) != 0) offset += 3; // sensor status present
    if (value.length < offset + 2) return;
    final raw = value[offset] | (value[offset + 1] << 8);
    final decoded = _decodeSfloat(raw);
    if (decoded != null && decoded >= 50 && decoded <= 100) {
      telemetry.bloodOxygen = decoded.round();
      telemetry.hasBloodOxygenData = true;
      lastRealTelemetryAt = DateTime.now();
      log('Standard PLX oxygen measurement: ${telemetry.bloodOxygen}%');
      onData?.call();
    }
  }

  double? _decodeSfloat(int raw) {
    var mantissa = raw & 0x0fff;
    var exponent = (raw >> 12) & 0x0f;
    if (mantissa >= 0x0800) mantissa -= 0x1000;
    if (exponent >= 0x08) exponent -= 0x10;
    // Reserved/NaN SFLOAT special values are not health measurements.
    if (mantissa == -2048 || mantissa == -2047 || mantissa == -2046 || mantissa == -2045) return null;
    return mantissa * math.pow(10, exponent).toDouble();
  }

  Future<bool> _sendCommand(MtkCommand command) async {
    return _writePackets(<List<int>>[command.frame, if (command.data.isNotEmpty) command.data]);
  }

  Future<bool> _sendWwCommand(String body) async {
    if (!isConnected || writeChar == null) return false;
    try {
      return await _sendCommand(await MtkProtocol.ww(body));
    } catch (e) {
      log('Could not encode "$body": $e');
      return false;
    }
  }

  Future<bool> _writePackets(List<List<int>> packets) async {
    final previous = _writeTail;
    final release = Completer<void>();
    _writeTail = release.future;
    await previous.catchError((Object _) {});
    try {
      if (!isConnected || device == null || writeChar == null) {
        log('Write skipped: watch is disconnected.');
        return false;
      }
      for (final packet in packets) {
        if (packet.isEmpty) continue;
        const chunkSize = 20; // Conservative legacy-safe MTK2502 packet size.
        for (var i = 0; i < packet.length; i += chunkSize) {
          if (!isConnected || writeChar == null) return false;
          final end = math.min(i + chunkSize, packet.length).toInt();
          await writeChar!.write(packet.sublist(i, end), withoutResponse: false);
          if (i + chunkSize < packet.length) {
            await Future<void>.delayed(const Duration(milliseconds: 12));
          }
        }
      }
      return true;
    } catch (e) {
      log('GATT write failed (not a watch-level acknowledgement): $e');
      return false;
    } finally {
      release.complete();
    }
  }

  void triggerFindPhoneAlarm() {
    if (isPhoneRinging) return;
    isPhoneRinging = true;
    unawaited(_phoneChannel.invokeMethod<void>('startAlarm').catchError((Object e) {
      log('Phone ring could not start: $e');
    }));
    onFindPhoneTriggered?.call();
    onData?.call();
    log('Find-phone alarm triggered by the watch.');
  }

  void stopFindPhoneAlarm() {
    isPhoneRinging = false;
    unawaited(_phoneChannel.invokeMethod<void>('stopAlarm').catchError((Object e) {
      log('Phone ring stop failed: $e');
    }));
    unawaited(_sendWwCommand('10,4,0'));
    onData?.call();
  }

  Future<void> autoSyncTime12Hour() async {
    telemetry.is12Hour = true;
    try {
      await _ctsChannel.invokeMethod<bool>('setTimeFormat', <String, Object>{'is12Hour': true});
      await _ctsChannel.invokeMethod<bool>('broadcastCtsTime');
    } catch (e) {
      log('Phone-side time GATT profile update failed: $e');
    }
    final ok = await _sendWwCommand('SET,40,0');
    if (ok) {
      log('12-hour format command written. Verify on the watch; GATT write is not an application-level acknowledgement.');
    }
    if (isProtocolReady) await _syncNativeTime();
    onData?.call();
  }

  Future<void> setTimeFormat({required bool is12Hour}) async {
    telemetry.is12Hour = is12Hour;
    try {
      await _ctsChannel.invokeMethod<bool>('setTimeFormat', <String, Object>{'is12Hour': is12Hour});
      await _ctsChannel.invokeMethod<bool>('broadcastCtsTime');
    } catch (e) {
      log('Could not update the phone-side time format profile: $e');
    }
    final command = await _sendWwCommand(is12Hour ? 'SET,40,0' : 'SET,40,1');
    log(command
        ? '${is12Hour ? '12-hour' : '24-hour'} setting command written; verify it on the watch.'
        : 'Time-format command was not sent.');
    onData?.call();
  }

  Future<void> _syncNativeTime() async {
    if (!isConnected || !isProtocolReady) return;
    try {
      final cmd = await MtkProtocol.syncTime(version: deviceVersion ?? 0);
      final ok = await _sendCommand(cmd);
      log(ok
          ? 'Native time-sync frame written. The watch may still reject it; check displayed time.'
          : 'Native time-sync write failed.');
    } catch (e) {
      log('Time synchronization failed: $e');
    }
  }

  Future<void> queryAllHealthData() async {
    if (!isConnected || !isProtocolReady) {
      log('Health query skipped: MediaTek protocol handshake has not been acknowledged.');
      return;
    }
    final commands = <String>[
      'GET,10', // WWfit device / battery status query
      '01,1', // steps
      'PS,GET', // WWfit pedometer query
      '03,1', // heart-rate request
      '04,1', // blood-pressure request
      '05,1', // stress/fatigue-related stream in this firmware
      '11,1', // temperature request
    ];
    for (final body in commands) {
      final ok = await _sendWwCommand(body);
      if (!ok) {
        log('Stopped health query sequence because "$body" could not be written.');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    try {
      final pedometer = await MtkProtocol.kctPedometer();
      await _sendCommand(pedometer);
    } catch (e) {
      log('KCT pedometer command could not be encoded: $e');
    }
    log('Health queries sent. Cards change only when a recognizable response arrives.');
  }

  Future<void> readSigBattery() async {
    final characteristic = batteryChar;
    if (characteristic == null) {
      log('Standard BLE battery characteristic 0x2A19 not available.');
      return;
    }
    try {
      final value = await characteristic.read();
      if (value.isNotEmpty && value.first >= 0 && value.first <= 100) {
        telemetry.batteryLevel = value.first;
        telemetry.hasBatteryData = true;
        log('Battery reading: ${value.first}% (standard BLE characteristic).');
        onData?.call();
      }
    } catch (e) {
      log('Battery read failed: $e');
    }
  }

  Future<void> measureHeartRateLive() async {
    if (!isProtocolReady) {
      log('Heart-rate request skipped: protocol handshake is not ready.');
      return;
    }
    final ok = await _sendWwCommand('03,1');
    log(ok ? 'Heart-rate measurement requested; waiting for actual response.' : 'Heart-rate request failed.');
  }

  Future<void> saveAlarm(WatchAlarm alarm) async {
    if (!telemetry.alarms.any((item) => identical(item, alarm))) telemetry.alarms.add(alarm);
    // The exact watch-alarm serialization path was not present in the exported
    // class excerpts. Never send invented SET,ALARM packets to firmware.
    log('Alarm held in memory for this app session only. Nothing was written to the watch; its alarm packet format is not yet verified.');
    onData?.call();
  }

  Future<void> setDrinkWaterReminder(bool enabled, int interval) async {
    telemetry.isDrinkWaterEnabled = enabled;
    telemetry.drinkWaterIntervalMinutes = interval.clamp(5, 240).toInt();
    // A UI-level state change is not reported as a watch-side success.
    log('Water reminder preference held in memory for this app session only. No watch setting was changed because its packet format is not yet verified.');
    onData?.call();
  }

  Future<void> ringWatch() async {
    final characteristic = alertChar;
    if (characteristic == null) {
      log('Find-watch is unavailable: Immediate Alert characteristic 0x2A06 was not discovered.');
      return;
    }
    try {
      // The original app's standard Immediate Alert service is the confirmed
      // working path: 0x1802 / 0x2A06, value 0x02 = high alert.
      await characteristic.write(<int>[0x02], withoutResponse: false);
      log('Find-watch alert value written to standard Immediate Alert characteristic.');
    } catch (e) {
      log('Find-watch command failed: $e');
    }
  }


  String _notificationAppName(String packageName) {
    const names = <String, String>{
      'com.whatsapp': 'WhatsApp',
      'com.facebook.katana': 'Facebook',
      'com.instagram.android': 'Instagram',
      'com.twitter.android': 'X',
      'com.google.android.apps.messaging': 'Messages',
      'com.android.messaging': 'Messages',
      'com.google.android.gm': 'Gmail',
    };
    return names[packageName] ?? 'Phone notification';
  }

  Future<void> pushNotification(String title, String body, {String appId = 'com.example.ht99_companion'}) async {
    if (!isConnected || !isProtocolReady) {
      log('Notification skipped: the MediaTek protocol handshake is not ready.');
      return;
    }
    try {
      final command = await MtkProtocol.notification(
        title: title,
        body: body,
        appName: appId,
        appId: appId,
      );
      final ok = await _sendCommand(command);
      log(ok
          ? 'Notification XML written to the native DATA channel; watch display confirmation is not available.'
          : 'Notification write failed.');
    } catch (e) {
      log('Notification could not be encoded: $e');
    }
  }

  Future<bool> syncWeather({String city = 'Karachi', double latitude = 24.8607, double longitude = 67.0011}) async {
    if (!isConnected || !isProtocolReady) {
      log('Weather sync skipped: the MediaTek protocol handshake is not ready.');
      return false;
    }
    HttpClient? client;
    try {
      log('Fetching current weather for $city from Open-Meteo.');
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', <String, String>{
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current': 'temperature_2m,weather_code',
        'daily': 'temperature_2m_max,temperature_2m_min',
        'timezone': 'auto',
        'forecast_days': '1',
      });
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        log('Weather service returned HTTP ${response.statusCode}.');
        return false;
      }
      final jsonText = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
      final current = decoded['current'] as Map<String, dynamic>?;
      final daily = decoded['daily'] as Map<String, dynamic>?;
      final temp = (current?['temperature_2m'] as num?)?.round();
      final code = (current?['weather_code'] as num?)?.toInt();
      final high = (daily?['temperature_2m_max'] as List?)?.firstOrNull;
      final low = (daily?['temperature_2m_min'] as List?)?.firstOrNull;
      if (temp == null || code == null || high is! num || low is! num) {
        log('Weather response did not contain all required current/high/low fields.');
        return false;
      }
      final condition = _weatherLabel(code);
      final command = await MtkProtocol.weather(
        city: city,
        condition: condition,
        currentC: temp,
        highC: high.round(),
        lowC: low.round(),
      );
      final ok = await _sendCommand(command);
      log(ok
          ? 'Weather payload written: $city $condition $temp°C (high ${high.round()}°, low ${low.round()}°). Confirm the watch display.'
          : 'Weather payload write failed.');
      return ok;
    } catch (e) {
      log('Weather sync failed: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  String _weatherLabel(int code) {
    if (code == 0) return 'Sunny';
    if (code <= 3) return 'Cloudy';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain';
    if (code >= 85 && code <= 86) return 'Snow';
    if (code >= 95) return 'Thunderstorm';
    return 'Cloudy';
  }

  Future<void> pushWeather(int tempC, int conditionCode, int highC, int lowC) async {
    if (!isConnected || !isProtocolReady) return;
    try {
      final command = await MtkProtocol.weather(
        city: 'Karachi',
        condition: _weatherLabel(conditionCode),
        currentC: tempC,
        highC: highC,
        lowC: lowC,
      );
      final ok = await _sendCommand(command);
      log(ok ? 'Weather command written; confirm on watch.' : 'Weather command write failed.');
    } catch (e) {
      log('Weather packet failed: $e');
    }
  }

  Future<bool> writeRaw(List<int> bytes) => _writePackets(<List<int>>[bytes]);

  Future<void> disconnect() async {
    await stopScan();
    try { await _connectionSub?.cancel(); } catch (_) {}
    _connectionSub = null;
    for (final subscription in _notifySubs) {
      try { await subscription.cancel(); } catch (_) {}
    }
    _notifySubs.clear();
    final current = device;
    isConnected = false;
    isConnecting = false;
    isProtocolReady = false;
    _versionCompleter = null;
    try { await current?.disconnect(); } catch (_) {}
    await _clearConnectionReferences();
    try { await _ctsChannel.invokeMethod<void>('stopCtsServer'); } catch (_) {}
    log('Watch disconnected.');
    onStatus?.call('Disconnected');
    onData?.call();
  }

  Future<void> _handleRemoteDisconnect() async {
    isConnected = false;
    isConnecting = false;
    isProtocolReady = false;
    _versionCompleter = null;
    await _clearConnectionReferences();
    onStatus?.call('Watch disconnected');
    log('Watch link disconnected by the device.');
    onData?.call();
  }

  Future<void> _clearConnectionReferences() async {
    for (final subscription in _notifySubs) {
      try { await subscription.cancel(); } catch (_) {}
    }
    _notifySubs.clear();
    try { await _connectionSub?.cancel(); } catch (_) {}
    _connectionSub = null;
    device = null;
    writeChar = null;
    notifyChar = null;
    alertChar = null;
    batteryChar = null;
    heartRateChar = null;
    oxygenChar = null;
    _rxBuffer.clear();
    _pendingRx = null;
  }
}

extension _RangeCheck on int {
  bool inRange(int minimum, int maximum) => this >= minimum && this <= maximum;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
