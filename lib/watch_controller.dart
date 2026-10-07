import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WatchController {
  static const String targetMac = "F9:47:B2:F6:EC:7C";

  // Extracted Shenzhen KCT & MTK Service & Char UUIDs
  static final List<String> targetServices = [
    "c3e6fea0-e966-1000-8000-be99c223df6a",
    "0783b03e-8535-b5a0-7140-a304d2495cb7",
    "0000fee7-0000-1000-8000-00805f9b34fb",
    "0000fea0-0000-1000-8000-00805f9b34fb",
    "b75c49d2-04a3-4071-a0b5-35853eb08307",
  ];

  static final List<String> writeCharList = [
    "c3e6fea1-e966-1000-8000-be99c223df6a",
    "0783b03e-8535-b5a0-7140-a304d2495cba",
    "0783b03e-8535-b5a0-7140-a304d2495cb8",
  ];

  static final List<String> notifyCharList = [
    "c3e6fea2-e966-1000-8000-be99c223df6a",
    "0783b03e-8535-b5a0-7140-a304d2495cb8",
    "0000fea1-0000-1000-8000-00805f9b34fb",
  ];

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  StreamSubscription? _scanSub;
  StreamSubscription? _notifySub;

  // Live Watch State
  int batteryLevel = 0;
  int stepCount = 0;

  // Safe string helper (prevents any RangeError)
  String safeUuidStr(Guid guid) {
    String s = guid.str;
    return s.length > 8 ? s.substring(0, 8) : s;
  }

  Future<void> connectToWatch({
    required Function(String) onStatus,
    required Function() onConnected,
    required Function() onDataUpdated,
  }) async {
    onStatus("Scanning for HT99...");

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      onStatus("Scan failed: $e");
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String deviceMac = r.device.remoteId.str.toUpperCase();
        String deviceName = r.device.platformName;

        if (deviceMac == targetMac || deviceName == "HT99") {
          onStatus("Found HT99 ($deviceMac). Connecting...");
          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();

          await _bindDevice(r.device, onStatus, onConnected, onDataUpdated);
          break;
        }
      }
    });
  }

  Future<void> _bindDevice(
    BluetoothDevice device,
    Function(String) onStatus,
    Function() onConnected,
    Function() onDataUpdated,
  ) async {
    try {
      await device.connect(
        license: License.free,
        autoConnect: false,
        mtu: 256,
      );
      connectedDevice = device;

      onStatus("Connected. Discovering services...");
      List<BluetoothService> services = await device.discoverServices();

      // 1. Locate Write (TX) and Notify (RX) Characteristics
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic c in service.characteristics) {
          String cUuid = c.uuid.str.toLowerCase();

          // Match Write Channel
          if (writeChar == null &&
              (writeCharList.contains(cUuid) ||
                  c.properties.writeWithoutResponse ||
                  c.properties.write)) {
            writeChar = c;
          }

          // Match Notify Channel
          if (notifyChar == null &&
              (notifyCharList.contains(cUuid) ||
                  c.properties.notify ||
                  c.properties.indicate)) {
            notifyChar = c;
          }
        }
      }

      if (writeChar == null) {
        onStatus("Connected, but no writable channel found.");
        return;
      }

      // 2. Enable Notifications for incoming watch data
      if (notifyChar != null) {
        try {
          await notifyChar!.setNotifyValue(true);
          _notifySub = notifyChar!.lastValueStream.listen((data) {
            _parseIncomingWatchPacket(data, onDataUpdated);
          });
        } catch (_) {}
      }

      onStatus("Ready! Bound to [${safeUuidStr(writeChar!.uuid)}]");
      onConnected();

      // Automatically sync time and fetch status upon connection
      await Future.delayed(const Duration(milliseconds: 300));
      await syncTimeNow();
      await requestBatteryAndSteps();
    } catch (e) {
      onStatus("Connection error: $e");
    }
  }

  // Parses incoming data from HT99 (Battery, Steps, Button presses)
  void _parseIncomingWatchPacket(List<int> data, Function() onDataUpdated) {
    if (data.isEmpty) return;

    // Standard KCT packet response: Header 0xAB
    if (data[0] == 0xAB && data.length >= 4) {
      int cmdId = data[2];

      // Battery level response
      if (cmdId == 0x91 || cmdId == 0x08) {
        batteryLevel = data[3].clamp(0, 100);
        onDataUpdated();
      }
      // Step counter response
      else if (cmdId == 0x51 && data.length >= 7) {
        stepCount = (data[4] << 16) | (data[5] << 8) | data[6];
        onDataUpdated();
      }
    }
  }

  Future<bool> sendBytes(List<int> bytes) async {
    if (writeChar == null) return false;

    const int chunkSize = 20;
    int length = bytes.length;

    try {
      if (length <= chunkSize) {
        await writeChar!.write(
          bytes,
          withoutResponse: writeChar!.properties.writeWithoutResponse,
        );
        return true;
      }

      for (int i = 0; i < length; i += chunkSize) {
        int end = (i + chunkSize < length) ? i + chunkSize : length;
        List<int> chunk = bytes.sublist(i, end);
        await writeChar!.write(
          chunk,
          withoutResponse: writeChar!.properties.writeWithoutResponse,
        );
        await Future.delayed(const Duration(milliseconds: 20));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // Command 1: Synchronize Date and Time
  Future<void> syncTimeNow() async {
    DateTime now = DateTime.now();
    List<int> timePacket = [
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
    await sendBytes(timePacket);
  }

  // Command 2: Trigger Watch Vibration (Find Watch)
  Future<void> findWatch() async {
    List<int> findPacket = [0xAB, 0x00, 0x03, 0x01];
    await sendBytes(findPacket);
  }

  // Command 3: Request Battery and Activity Telemetry
  Future<void> requestBatteryAndSteps() async {
    await sendBytes([0xAB, 0x00, 0x91]); // Battery Request
    await Future.delayed(const Duration(milliseconds: 50));
    await sendBytes([0xAB, 0x00, 0x51]); // Steps Request
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await connectedDevice?.disconnect();
    connectedDevice = null;
    writeChar = null;
    notifyChar = null;
  }
}
