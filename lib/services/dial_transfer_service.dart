import 'dart:async';
import 'watch_ble_service.dart';

class DialTransferService {
  final WatchBleService bleService;

  DialTransferService(this.bleService);

  // Transfers 320x385 .dat binary data using MTK FOTA packet sizing
  Future<void> uploadDial(
      List<int> dialBytes, Function(double) onProgress) async {
    bleService.log("Initiating Dial Push (${dialBytes.length} bytes)...");

    // Slicing in 20-byte chunks conforming to MTK FOTA protocol
    const int chunkSize = 20;
    int total = dialBytes.length;

    for (int i = 0; i < total; i += chunkSize) {
      int end = (i + chunkSize < total) ? i + chunkSize : total;
      List<int> chunk = dialBytes.sublist(i, end);

      await bleService.writeRaw(chunk);
      onProgress(end / total);

      // Regulate transmission speed to prevent buffer overruns
      await Future.delayed(const Duration(milliseconds: 12));
    }

    bleService.log("Dial push transfer complete.");
  }
}
