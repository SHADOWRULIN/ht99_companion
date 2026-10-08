import 'dart:async';
import 'watch_ble_service.dart';

class DialService {
  final WatchBleService ble;

  DialService(this.ble);

  Future<void> sendDialDat(
      List<int> datBytes, Function(double) onProgress) async {
    ble.log("Starting dial push (${datBytes.length} bytes)...");
    const int chunkSize = 20;
    int total = datBytes.length;

    for (int i = 0; i < total; i += chunkSize) {
      int end = (i + chunkSize < total) ? i + chunkSize : total;
      List<int> chunk = datBytes.sublist(i, end);
      await ble.writeRaw(chunk);
      onProgress(end / total);
      await Future.delayed(const Duration(milliseconds: 14));
    }
    ble.log("Dial push complete.");
  }
}
