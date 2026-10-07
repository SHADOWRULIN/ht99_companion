import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WatchController {
  static const String targetMac = "F9:47:B2:F6:EC:7C";

  // All known KCT & MediaTek Service UUIDs from s1.g
  static final List<String> targetServices = [
    "c3e6fea0-e966-1000-8000-be99c223df6a",
    "0783b03e-8535-b5a0-7140-a304d2495cb7",
    "b75c49d2-04a3-4071-a0b5-35853eb08307",
    "0000fea0-0000-1000-8000-00805f9b34fb",
    "0000fee7-0000-1000-8000-00805f9b34fb",
  ];

  // All known write characteristic UUIDs from s1.g
  static final List<String> targetCharacteristics = [
    "c3e6fea1-e966-1000-8000-be99c223df6a",
    "0783b03e-8535-b5a0-7140-a304d2495cba",
    "0783b03e-8535-b5a0-7140-a304d2495cb8",
    "c3e6fea2-e966-1000-8000-be99c223df6a",
  ];

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;
  StreamSubscription? _scanSub;

  Future<void> connectToWatch({
    required Function(String) onStatus,
    required Function() onConnected,
  }) async {
    onStatus("Scanning for HT99...");

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String deviceMac = r.device.remoteId.str.toUpperCase();
        String deviceName = r.device.platformName;

        if (deviceMac == targetMac || deviceName == "HT99") {
          onStatus("Found HT99! Connecting...");
          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();

          await _bindDevice(r.device, onStatus, onConnected);
          break;
        }
      }
    });
  }

  Future<void> _bindDevice(
    BluetoothDevice device,
    Function(String) onStatus,
    Function() onConnected,
  ) async {
    try {
      onStatus("Connecting...");
      await device.connect(
        license: License.free,
        autoConnect: false,
        mtu: 256,
      );
      connectedDevice = device;

      onStatus("Discovering watch services...");
      List<BluetoothService> services = await device.discoverServices();

      List<String> foundServiceUuids = [];

      // 1. Check for exact KCT characteristic match
      for (BluetoothService service in services) {
        String sUuid = service.uuid.str.toLowerCase();
        foundServiceUuids.add(sUuid);

        for (BluetoothCharacteristic characteristic in service.characteristics) {
          String cUuid = characteristic.uuid.str.toLowerCase();

          if (targetCharacteristics.contains(cUuid)) {
            writeCharacteristic = characteristic;
            onStatus("Ready! Bound to KCT Characteristic.");
            onConnected();
            return;
          }
        }
      }

      // 2. Fallback: Automatically latch onto any writable characteristic
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.writeWithoutResponse ||
              characteristic.properties.write) {
            writeCharacteristic = characteristic;
            onStatus("Ready! Bound to writable: ${characteristic.uuid.str.substring(0, 8)}...");
            onConnected();
            return;
          }
        }
      }

      // 3. If no writable characteristic exists, display the found services
      onStatus("No writable channel found.\nServices:\n${foundServiceUuids.join('\n')}");
    } catch (e) {
      onStatus("Connection error: $e");
    }
  }

  Future<bool> sendBytes(List<int> bytes) async {
    if (writeCharacteristic == null) return false;

    const int chunkSize = 20;
    int length = bytes.length;

    if (length <= chunkSize) {
      await writeCharacteristic!.write(
        bytes,
        withoutResponse: writeCharacteristic!.properties.writeWithoutResponse,
      );
      return true;
    }

    for (int i = 0; i < length; i += chunkSize) {
      int end = (i + chunkSize < length) ? i + chunkSize : length;
      List<int> chunk = bytes.sublist(i, end);
      await writeCharacteristic!.write(
        chunk,
        withoutResponse: writeCharacteristic!.properties.writeWithoutResponse,
      );
      await Future.delayed(const Duration(milliseconds: 15));
    }

    return true;
  }

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
}