import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class DeviceInfoService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Get device model, manufacturer, OS version.
  Future<String> getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return '${info.manufacturer} ${info.model}, Android ${info.version.release} (API ${info.version.sdkInt})';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return '${info.model}, iOS ${info.systemVersion}';
      }
      return 'Unknown device';
    } catch (e) {
      return 'Error reading device info: $e';
    }
  }

  /// Get battery level info.
  Future<String> getBatteryLevel() async {
    try {
      // Use a simple approach: report what we can determine
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        final battery = info.batteryPercentage;
        if (battery != null) {
          return '${battery.toStringAsFixed(0)}%';
        }
        return 'Unknown (battery info not available)';
      }
      return 'Battery info only available on Android';
    } catch (e) {
      return 'Error reading battery: $e';
    }
  }

  /// Get storage info.
  Future<String> getStorageInfo() async {
    try {
      // Report basic storage info from Android
      if (Platform.isAndroid) {
        final storage = await _deviceInfo.androidInfo;
        final totalStorage = storage.totalStorage;
        final freeStorage = storage.freeStorage;
        if (totalStorage != null && freeStorage != null) {
          final used = totalStorage - freeStorage;
          final usedGb = (used / (1024 * 1024 * 1024)).toStringAsFixed(1);
          final totalGb = (totalStorage / (1024 * 1024 * 1024)).toStringAsFixed(1);
          return '${usedGb}GB used / ${totalGb}GB total';
        }
        return 'Total: unknown, Free: unknown';
      }
      return 'Storage info only available on Android';
    } catch (e) {
      return 'Error reading storage: $e';
    }
  }

  /// Get memory (RAM) info.
  Future<String> getMemoryInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        final totalRam = info.totalRAM;
        final freeRam = info.freeRAM;
        if (totalRam != null) {
          final totalGb = (totalRam / (1024 * 1024 * 1024)).toStringAsFixed(1);
          if (freeRam != null) {
            final freeGb = (freeRam / (1024 * 1024 * 1024)).toStringAsFixed(1);
            return '${freeGb}GB free / ${totalGb}GB total RAM';
          }
          return '${totalGb}GB total RAM';
        }
        return 'RAM info not available';
      }
      return 'RAM info only available on Android';
    } catch (e) {
      return 'Error reading memory: $e';
    }
  }
}
