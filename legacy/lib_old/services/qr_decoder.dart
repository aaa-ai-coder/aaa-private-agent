import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Pure-Dart QR decoder used to recover saved WiFi passwords from the
/// Android "Share" QR screen. The QR payload follows the WPA configuration
/// format: `WIFI:S:<ssid>;T:WPA;P:<password>;;`
class QrDecoder {
  /// Decode the first QR code found in a PNG file. Returns the raw text.
  static String? decodePngFile(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      return decodePngBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Decode the first QR code found in PNG bytes.
  static String? decodePngBytes(List<int> bytes) {
    try {
      final image = img.decodeImage(Uint8List.fromList(bytes));
      if (image == null) return null;
      final source = RGBLuminanceSource(
        image.width,
        image.height,
        image
            .convert(numChannels: 4)
            .getBytes(order: img.ChannelOrder.abgr)
            .buffer
            .asInt32List(),
      );
      final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
      final reader = QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text;
    } catch (_) {
      return null;
    }
  }

  /// Parse a WPA QR payload into a [WifiQrInfo]. Returns null when the payload
  /// is not a valid WiFi config.
  static WifiQrInfo? parseWifiQr(String payload) {
    if (!payload.trimLeft().toUpperCase().startsWith('WIFI:')) return null;
    String? ssid;
    String? password;
    String? security;
    final body = payload.trim().substring(5);
    for (final part in body.split(';')) {
      if (part.contains(':')) {
        final key = part.substring(0, part.indexOf(':')).toUpperCase();
        final value = part.substring(part.indexOf(':') + 1);
        if (key == 'S') ssid = value;
        if (key == 'P') password = value;
        if (key == 'T') security = value;
      }
    }
    if (ssid == null) return null;
    return WifiQrInfo(
      ssid: ssid,
      password: password,
      security: security ?? 'WPA',
    );
  }
}

class WifiQrInfo {
  final String ssid;
  final String? password;
  final String security;

  const WifiQrInfo({
    required this.ssid,
    required this.password,
    required this.security,
  });
}
