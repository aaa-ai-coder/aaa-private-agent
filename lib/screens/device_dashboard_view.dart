import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../services/local_llm_service.dart';
import '../theme/app_theme.dart';

/// Device Dashboard tab: live battery, RAM, storage, phone info, the on-device
/// AI model status and quick brightness/volume controls. Auto-refreshes so a
/// low-end phone (like the Samsung A30) can keep an eye on resources.
class DeviceDashboardView extends StatefulWidget {
  final bool isDark;
  final VoidCallback onOpenSettings;

  const DeviceDashboardView({
    super.key,
    required this.isDark,
    required this.onOpenSettings,
  });

  @override
  State<DeviceDashboardView> createState() => _DeviceDashboardViewState();
}

class _DeviceDashboardViewState extends State<DeviceDashboardView> {
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final VolumeController _volume = VolumeController();
  final ScreenBrightness _brightness = ScreenBrightness();

  Timer? _timer;

  int _batteryLevel = -1;
  bool _charging = false;
  int _ramTotalMb = 0;
  int _ramFreeMb = 0;
  int _diskTotal = 0;
  int _diskFree = 0;
  String _deviceName = 'Unknown device';
  String _osVersion = 'Android';
  int _sdkInt = 0;
  double _brightness = 0.5;
  double _volumeLevel = 0.5;
  bool _sliderBusy = false;
  LocalModelOption? _aiModel;
  bool? _aiReady;

  @override
  void initState() {
    super.initState();
    _refreshHardware();
    _refreshControls();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshHardware();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshHardware() async {
    try {
      final level = await _battery.batteryLevel;
      var charging = false;
      try {
        charging = await _battery.isCharging();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _batteryLevel = level;
        _charging = charging;
      });
    } catch (_) {}

    try {
      final info = await _deviceInfo.androidInfo;
      if (!mounted) return;
      setState(() {
        _ramTotalMb = info.physicalRamSize;
        _ramFreeMb = info.availableRamSize;
        _diskTotal = info.totalDiskSize;
        _diskFree = info.freeDiskSize;
        _deviceName =
            info.manufacturer.isEmpty ? 'Unknown device' : '${info.manufacturer} ${info.model}';
        _osVersion =
            'Android ${info.version.release} (API ${info.version.sdkInt})';
        _sdkInt = info.version.sdkInt;
      });
    } catch (_) {}

    try {
      final model = await LocalLlmService.instance.selectedModel();
      final ready = await LocalLlmService.instance.isDownloaded();
      if (!mounted) return;
      setState(() {
        _aiModel = model;
        _aiReady = ready;
      });
    } catch (_) {}
  }

  Future<void> _refreshControls() async {
    try {
      final v = await _volume.getVolume();
      if (mounted) setState(() => _volumeLevel = v.clamp(0.0, 1.0));
    } catch (_) {}
    try {
      final b = await _brightness.getScreenBrightness();
      if (mounted) setState(() => _brightness = b.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> _setVolume(double v) async {
    if (_sliderBusy) return;
    _sliderBusy = true;
    setState(() => _volumeLevel = v);
    try {
      _volume.showSystemUI = false;
      await _volume.setVolume(v);
    } catch (_) {}
    _sliderBusy = false;
  }

  Future<void> _setBrightness(double v) async {
    if (_sliderBusy) return;
    _sliderBusy = true;
    setState(() => _brightness = v);
    try {
      await _brightness.setScreenBrightness(v);
    } catch (_) {}
    _sliderBusy = false;
  }

  String _gb(int bytes) {
    if (bytes <= 0) return '-';
    return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final subColor = widget.isDark
        ? const Color(0xFFA8938C)
        : const Color(0xFF6B5A52);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const SizedBox(height: 4),
        Text(
          'Device Dashboard',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Live resources, phone info and on-device AI status',
          style: TextStyle(fontSize: 12.5, color: subColor),
        ),
        const SizedBox(height: 16),

        _dashCard(
          context,
          icon: _charging
              ? Icons.battery_charging_full_rounded
              : (_batteryLevel < 20
                  ? Icons.battery_alert_rounded
                  : Icons.battery_std_rounded),
          color: _batteryLevel < 20 ? AppColors.danger : const Color(0xFF2FBF8F),
          title: 'Battery',
          value: _batteryLevel < 0 ? '--%' : '$_batteryLevel%',
          child: _levelBar(
            _batteryLevel < 0 ? 0 : _batteryLevel / 100,
            _batteryLevel < 20 ? AppColors.danger : const Color(0xFF2FBF8F),
          ),
          subtitle: _charging ? 'Charging' : null,
        ),

        _dashCard(
          context,
          icon: Icons.memory_rounded,
          color: const Color(0xFF38A6F5),
          title: 'Memory (RAM)',
          value: _ramTotalMb > 0
              ? '${(_ramFreeMb / 1024).toStringAsFixed(1)} GB free'
              : '--',
          child: _levelBar(
            _ramTotalMb > 0
                ? (_ramTotalMb - _ramFreeMb) / _ramTotalMb
                : 0,
            const Color(0xFF38A6F5),
          ),
          subtitle: _ramTotalMb > 0
              ? '${(_ramTotalMb / 1024).toStringAsFixed(1)} GB total'
              : null,
        ),

        _dashCard(
          context,
          icon: Icons.storage_rounded,
          color: const Color(0xFFFFB020),
          title: 'Storage',
          value: _diskTotal > 0
              ? '${_gb(_diskTotal - _diskFree)} GB used'
              : '--',
          child: _levelBar(
            _diskTotal > 0
                ? (_diskTotal - _diskFree) / _diskTotal
                : 0,
            const Color(0xFFFFB020),
          ),
          subtitle:
              _diskTotal > 0 ? '${_gb(_diskTotal)} GB total' : null,
        ),

        _dashCard(
          context,
          icon: Icons.smartphone_rounded,
          color: const Color(0xFFFF8A5C),
          title: 'Device',
          value: _deviceName,
          child: const SizedBox(height: 2),
          subtitle: _osVersion,
        ),

        _dashCard(
          context,
          icon: Icons.phonelink_erase_rounded,
          color: const Color(0xFF2FBF8F),
          title: 'On-Device AI',
          value: _aiModel?.name ?? 'Qwen 2.5 0.5B',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _aiReady == true
                        ? Icons.check_circle_rounded
                        : Icons.cloud_download_rounded,
                    size: 16,
                    color: _aiReady == true
                        ? const Color(0xFF2FBF8F)
                        : subColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _aiReady == true
                          ? '${_aiModel?.name ?? 'Model'} ready on this phone'
                          : '${_aiModel?.name ?? 'Model'} not downloaded yet',
                      style: TextStyle(fontSize: 12.5, color: subColor),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onOpenSettings,
                    child: const Text('Manage'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Size: ${_aiModel?.sizeLabel ?? '~620 MB'} · runs fully offline '
                '· uses RAM only while chatting',
                style: TextStyle(fontSize: 11, color: subColor),
              ),
            ],
          ),
        ),

        _dashCard(
          context,
          icon: Icons.brightness_6_rounded,
          color: const Color(0xFFFFB86B),
          title: 'Screen Brightness',
          value: '${(_brightness * 100).round()}%',
          child: Slider(
            value: _brightness,
            activeColor: const Color(0xFFFFB86B),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              _setBrightness(v);
            },
          ),
        ),

        _dashCard(
          context,
          icon: Icons.volume_up_rounded,
          color: const Color(0xFFFF8A5C),
          title: 'Media Volume',
          value: '${(_volumeLevel * 100).round()}%',
          child: Slider(
            value: _volumeLevel,
            activeColor: const Color(0xFFFF8A5C),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              _setVolume(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _levelBar(double value, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 7,
        backgroundColor: color.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Widget _dashCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required Widget child,
    String? subtitle,
  }) {
    final subColor = widget.isDark
        ? const Color(0xFFA8938C)
        : const Color(0xFF6B5A52);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: subColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
