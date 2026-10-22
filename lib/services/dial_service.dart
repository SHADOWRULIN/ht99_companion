import 'package:flutter/services.dart';
import 'mtk_protocol.dart';
import 'watch_ble_service.dart';

/// Integrity-checks bundled WWfit dial files. Upload is intentionally blocked
/// until the original MediaTek FOTA transfer manager is ported and verified.
/// The old repository sent guessed CAPC START/END strings and then reported a
/// successful install even when the watch ignored the stream.
class DialService {
  final WatchBleService ble;
  DialService(this.ble);

  Future<bool> pushPresetDial(
    String assetPath,
    Function(double) onProgress,
  ) async {
    try {
      if (!ble.isConnected) {
        ble.log('Dial upload cancelled: watch is not connected.');
        return false;
      }
      ble.log('Loading dial asset: $assetPath');
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.length < 33 || !await MtkProtocol.validateDialMd5(bytes)) {
        ble.log('Dial rejected: the 32-byte MediaTek MD5 header does not validate.');
        return false;
      }
      onProgress(0.0);
      ble.log('Dial integrity verified (${bytes.length} bytes).');
      ble.log('Upload stopped safely: original WWfit FOTA manager/ACK sequence is not yet ported.');
      ble.log('No dial data was sent; this avoids corrupting watch storage with guessed packets.');
      onProgress(0.0);
      return false;
    } catch (e) {
      ble.log('Dial validation failed: $e');
      return false;
    }
  }
}
