import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WatchController {
  // Target MAC Address found on your watch screen
  static const String targetMac = "F9:47:B2:F6:EC:7C";

  // The exact KCT UUIDs extracted from s1.g
  static final Guid serviceUuidPrimary =
      Guid("c3e6fea0-e966-1000-8000-be99c223df6a");
  static final Guid charUuidPrimary =
      Guid("c3e6fea1-e966-1000-8000-be99c223df6a");

  static final Guid serviceUuidSecondary =
      Guid("0783b03e-8535-b5a0-7140-a304d2495cb7");
  static final Guid charUuidSecondary =
      Guid("0783b03e-8535-b5a0-7140-a304d2495cba");

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;
  StreamSubscription? _scanSub;

// 1. Scan and Connect
  Future<void> connectToWatch({
    required Function(String) onStatus,
    required Function() onConnected,
  }) async {
    onStatus("Starting Bluetooth Scan...");

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

  // 2. Discover Services and Match Extracted UUIDs
  Future<void> _bindDevice(
    BluetoothDevice device,
    Function(String) onStatus,
    Function() onConnected,
  ) async {
    try {
      onStatus("Connecting with high-speed MTU...");

      // Pass License.free and MTU directly to connect()
      await device.connect(
        license: License.free,
        autoConnect: false,
        mtu: 256,
      );

      connectedDevice = device;
      onStatus("Connected! Discovering KCT Services...");

      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid == serviceUuidPrimary ||
            service.uuid == serviceUuidSecondary) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid == charUuidPrimary ||
                characteristic.uuid == charUuidSecondary) {
              writeCharacteristic = characteristic;
              onStatus("Ready! Bound to KCT Characteristic.");
              onConnected();
              return;
            }
          }
        }
      }

      onStatus("Device connected, but KCT service was not found.");
    } catch (e) {
      onStatus("Connection error: $e");
    }
  }

  // 3. Send Sliced Byte Packets (Mirroring com.kct.bluetooth.c.J)
  Future<bool> sendBytes(List<int> bytes) async {
    if (writeCharacteristic == null) return false;

    const int chunkSize = 20; // Default KCT packet slice size
    int length = bytes.length;

    if (length <= chunkSize) {
      await writeCharacteristic!.write(
        bytes,
        withoutResponse: true, // Corresponds to setWriteType(1)
      );
      return true;
    }

    // Packet chunking loop
    for (int i = 0; i < length; i += chunkSize) {
      int end = (i + chunkSize < length) ? i + chunkSize : length;
      List<int> chunk = bytes.sublist(i, end);
      await writeCharacteristic!.write(
        chunk,
        withoutResponse: true,
      );
      await Future.delayed(const Duration(milliseconds: 15));
    }

    return true;
  }

  // 4. Time Sync Packet (KCT Format)
  Future<void> syncTimeNow() async {
    DateTime now = DateTime.now();

    // Standard KCT RTC command array
    List<int> timePacket = [
      0xAB, // KCT packet header
      0x00,
      0x04, // Command ID: Time Sync
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
