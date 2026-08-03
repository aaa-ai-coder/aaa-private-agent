import 'dart:io' show Platform;
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceInfoService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Battery _battery = Battery();

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

  /// Get battery level (0-100).
  Future<String> getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      return '$level%';
    } catch (e) {
      return 'Error reading battery: $e';
    }
  }

  /// Get storage info.
  Future<String> getStorageInfo() async {
    try {
      if (Platform.isAndroid) {
        final storage = await _deviceInfo.androidInfo;
        final totalBytes = storage.totalDiskSize;
        final freeBytes = storage.freeDiskSize;
        if (totalBytes > 0) {
          final usedBytes = totalBytes - freeBytes;
          final usedGb = (usedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
          final totalGb = (totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
          return '${usedGb}GB used / ${totalGb}GB total';
        }
        return 'Storage info not available';
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
        // device_info_plus 13.x: physicalRamSize, availableRamSize (in MB)
        final totalMb = info.physicalRamSize;
        final freeMb = info.availableRamSize;
        final totalGb = (totalMb / 1024).toStringAsFixed(1);
        final freeGb = (freeMb / 1024).toStringAsFixed(1);
        if (totalMb > 0) {
          return '${freeGb}GB free / ${totalGb}GB total RAM';
        }
        return 'RAM info not available';
      }
      return 'RAM info only available on Android';
    } catch (e) {
      return 'Error reading memory: $e';
    }
  }
}
