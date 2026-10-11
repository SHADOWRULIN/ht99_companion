import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'watch_ble_service.dart';

class DialService {
  final WatchBleService ble;

  DialService(this.ble);

  /// Loads and pushes a real 320x385 .dat dial from the assets bundle
  Future<bool> pushPresetDial(
      String assetPath, Function(double) onProgress) async {
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

  /// Streams the binary dial data using MediaTek MTK2502 FOTA framing
  Future<bool> sendDialBinary(
      List<int> datBytes, Function(double) onProgress) async {
    if (!ble.isConnected || ble.writeChar == null) {
      ble.log("Dial push aborted: Watch not connected.");
      return false;
    }

    int totalSize = datBytes.length;
    ble.log("Initiating Dial Push ($totalSize bytes)...");

    // 1. Send FOTA / CAPC Transfer Header (Type 5: CAPC <file_size>)
    String initCommand = "CAPC START $totalSize";
    List<int> initPayload = utf8.encode(initCommand);
    List<int> initFrame = [
      0xF0,
      0xF0,
      0xF0,
      0xF1,
      (initPayload.length >> 24) & 0xFF,
      (initPayload.length >> 16) & 0xFF,
      (initPayload.length >> 8) & 0xFF,
      initPayload.length & 0xFF,
      ...initPayload,
    ];

    await ble.writeRaw(initFrame);
    await Future.delayed(const Duration(milliseconds: 150));

    // 2. Stream Binary Chunks with Flow Control (20-byte MTU slices)
    const int chunkSize = 20;
    for (int i = 0; i < totalSize; i += chunkSize) {
      if (!ble.isConnected) {
        ble.log("Dial transfer interrupted: Connection lost.");
        return false;
      }

      int end = (i + chunkSize < totalSize) ? i + chunkSize : totalSize;
      List<int> chunk = datBytes.sublist(i, end);

      await ble.writeRaw(chunk);
      onProgress(end / totalSize);

      // 12ms delay prevents buffer overrun in MTK2502 NOR flash
      await Future.delayed(const Duration(milliseconds: 12));
    }

    // 3. Send Transfer Complete Sentinel
    String finishCommand = "CAPC END";
    List<int> finishPayload = utf8.encode(finishCommand);
    List<int> finishFrame = [
      0xF0,
      0xF0,
      0xF0,
      0xF1,
      (finishPayload.length >> 24) & 0xFF,
      (finishPayload.length >> 16) & 0xFF,
      (finishPayload.length >> 8) & 0xFF,
      finishPayload.length & 0xFF,
      ...finishPayload,
    ];
    await ble.writeRaw(finishFrame);

    ble.log("Dial push complete. Watch applying watch face...");
    return true;
  }
}
