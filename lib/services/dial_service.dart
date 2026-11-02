import 'dart:async';
import 'package:flutter/services.dart';
import 'watch_ble_service.dart';

class DialService {
  final WatchBleService ble;

  DialService(this.ble);

  Future<bool> pushPresetDial(
    String assetPath,
    Function(double) onProgress,
  ) async {
    try {
      ble.log("Loading dial asset: $assetPath...");
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> dialBytes = data.buffer.asUint8List();
      return await sendDialBinary(dialBytes, onProgress);
    } catch (e) {
      ble.log("Failed to load dial asset: $e");
      return false;
    }
  }

  Future<bool> sendDialBinary(
    List<int> datBytes,
    Function(double) onProgress,
  ) async {
    if (!ble.isConnected) {
      ble.log("Dial push aborted: Watch is not connected.");
      return false;
    }

    // In h.java (lines 151-175), the first 32 bytes of a WWfit .dat file
    // are an ASCII MD5 checksum header that is stripped before streaming.
    List<int> payload = datBytes;
    if (datBytes.length > 64) {
      final first32 = datBytes.sublist(0, 32);
      final isHexMd5 = first32.every((b) =>
          (b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x46) ||
          (b >= 0x61 && b <= 0x66));
      if (isHexMd5) {
        payload = datBytes.sublist(32);
        ble.log("Stripped 32-byte MD5 header (${payload.length} binary bytes)");
      }
    }

    int totalSize = payload.length;
    ble.log("Streaming dial binary ($totalSize bytes)...");

    const int blockSize = 240;
    for (int i = 0; i < totalSize; i += blockSize) {
      if (!ble.isConnected) {
        ble.log("Dial transfer interrupted: Connection lost.");
        return false;
      }

      int end = (i + blockSize < totalSize) ? i + blockSize : totalSize;
      List<int> block = payload.sublist(i, end);

      await ble.writeRaw(block);

      try {
        onProgress(end / totalSize);
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 60));
    }

    ble.log("Dial stream finished.");
    return true;
  }
}
