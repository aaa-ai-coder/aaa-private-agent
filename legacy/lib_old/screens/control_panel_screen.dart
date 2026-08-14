import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent_action.dart';
import '../services/action_handler.dart';
import '../services/scheduler_service.dart';
import '../theme/app_theme.dart';

/// One-tap Phone Control Panel: every toggle calls the same action pipeline the
/// AI uses, so the human and the agent have identical device powers.
class ControlPanelScreen extends StatefulWidget {
  final ActionHandler actionHandler;

  const ControlPanelScreen({super.key, required this.actionHandler});

  @override
  State<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends State<ControlPanelScreen> {
  bool _busy = false;
  bool _shizukuOk = false;
  String _status = '';

  // Toggle state mirrors the last requested value (device truth is not
  // readable for every setting, so the panel tracks what it asked for).
  final Map<String, bool> _toggles = {
    'wifi': true,
    'bluetooth': true,
    'mobile_data': true,
    'airplane': false,
    'hotspot': false,
    'dnd': false,
    'auto_rotate': true,
    'flashlight': false,
  };

  @override
  void initState() {
    super.initState();
    _checkShizuku();
  }

  Future<void> _checkShizuku() async {
    final ok = await widget.actionHandler.shizuku.checkAvailability();
    if (mounted) {
      setState(() {
        _shizukuOk = ok;
        _status = ok
            ? 'Shizuku connected - full device control active'
            : 'Shizuku not running - toggles need Shizuku or root';
      });
    }
  }

  Future<void> _run(AgentAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final result = await widget.actionHandler.execute(action);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.details ?? (result.success ? 'Done' : 'Failed')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result.success ? AppColors.success : AppColors.danger,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  /// Ask for a single text value, then run the generated action.
  Future<void> _promptAndRun(
    String label,
    String hint,
    AgentAction Function(String value) buildAction,
  ) async {
    final controller = TextEditingController(text: hint);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurfaceHigh : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Enter value'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Run'),
            ),
          ],
        );
      },
    );
    if (value == null || value.isEmpty) return;
    await _run(buildAction(value));
  }

  /// Show a scheduling dialog: pick an action, a time and an optional repeat
  /// interval, then register it with the SchedulerService.
  Future<void> _scheduleAction() async {
    const presets = <_SchedulePreset>[
      _SchedulePreset(Icons.volume_up_rounded, 'Set Volume', 'set_volume', {'level': 50}),
      _SchedulePreset(Icons.alarm_rounded, 'Set Alarm', 'set_alarm', {'hour': 7, 'minute': 30, 'label': 'Wake up'}),
      _SchedulePreset(Icons.wifi_rounded, 'Toggle WiFi', 'toggle_wifi', {'enable': true}),
      _SchedulePreset(Icons.music_note_rounded, 'Play Music', 'control_media', {'command': 'play'}),
      _SchedulePreset(Icons.lock_rounded, 'Lock Screen', 'lock_screen', {}),
      _SchedulePreset(Icons.home_rounded, 'Go Home', 'go_home', {}),
      _SchedulePreset(Icons.apps_rounded, 'Open App', 'open_app', {'app_name': 'YouTube'}),
      _SchedulePreset(Icons.phone_in_talk_rounded, 'Make Call', 'make_call', {'contact_name': 'Mom'}),
      _SchedulePreset(Icons.sms_rounded, 'Send SMS', 'send_sms', {'contact_name': 'John', 'message': 'Hello'}),
      _SchedulePreset(Icons.do_not_disturb_rounded, 'Do Not Disturb', 'toggle_dnd', {'enable': true}),
    ];

    String actionType = 'set_alarm';
    Map<String, dynamic> params = {'hour': 7, 'minute': 30, 'label': 'Wake up'};
    final labelCtrl = TextEditingController(text: 'Wake up');
    final nowTime = TimeOfDay.now();
    final nextMinuteOfDay = nowTime.hour * 60 + nowTime.minute + 60;
    TimeOfDay time = TimeOfDay(
      hour: (nextMinuteOfDay ~/ 60) % 24,
      minute: nextMinuteOfDay % 60,
    );
    int repeatMinutes = 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkSurfaceHigh : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: const Text('Schedule Action'),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTION', style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                      )),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: presets.map((p) {
                          final selected = actionType == p.action;
                          return ChoiceChip(
                            avatar: Icon(p.icon, size: 16),
                            label: Text(p.label),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                actionType = p.action;
                                params = Map.of(p.params);
                                labelCtrl.text = p.label;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text('TIME', style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                      )),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.schedule_rounded, size: 18),
                              label: Text(
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: ctx,
                                  initialTime: time,
                                );
                                if (picked != null) {
                                  setState(() => time = picked);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                              ),
                              child: DropdownButton<int>(
                                value: repeatMinutes,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('Once')),
                                  DropdownMenuItem(value: 30, child: Text('Every 30 min')),
                                  DropdownMenuItem(value: 60, child: Text('Every hour')),
                                  DropdownMenuItem(value: 360, child: Text('Every 6 hours')),
                                  DropdownMenuItem(value: 1440, child: Text('Daily')),
                                ],
                                onChanged: (v) =>
                                    setState(() => repeatMinutes = v ?? 0),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: labelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Label',
                          hintText: 'e.g. Wake up',
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.add_alarm_rounded, size: 18),
                  label: const Text('Schedule'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final now = DateTime.now();
    var when = DateTime(
      now.year, now.month, now.day, time.hour, time.minute,
    );
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }

    await SchedulerService.instance.addTask(
      label: labelCtrl.text.trim().isEmpty ? actionType : labelCtrl.text.trim(),
      actionType: actionType,
      params: params,
      scheduledAt: when,
      repeatMinutes: repeatMinutes,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Scheduled for ${when.toString().split('.').first}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('Phone Control Panel'),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _statusBanner(isDark),
            const SizedBox(height: 20),
            _sectionLabel('Quick Toggles', isDark),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
              children: [
                _toggleTile(
                  isDark,
                  'WiFi',
                  Icons.wifi_rounded,
                  AppColors.info,
                  'wifi',
                  _toggle('toggle_wifi', 'wifi'),
                ),
                _toggleTile(
                  isDark,
                  'Bluetooth',
                  Icons.bluetooth_rounded,
                  AppColors.indigo,
                  'bluetooth',
                  _toggle('toggle_bluetooth', 'bluetooth'),
                ),
                _toggleTile(
                  isDark,
                  'Mobile Data',
                  Icons.network_cell_rounded,
                  AppColors.success,
                  'mobile_data',
                  _toggle('toggle_mobile_data', 'mobile_data'),
                ),
                _toggleTile(
                  isDark,
                  'Airplane',
                  Icons.flight_rounded,
                  AppColors.orange,
                  'airplane',
                  _toggle('toggle_airplane_mode', 'airplane'),
                ),
                _toggleTile(
                  isDark,
                  'Hotspot',
                  Icons.wifi_tethering_rounded,
                  AppColors.violet,
                  'hotspot',
                  _toggle('toggle_hotspot', 'hotspot'),
                ),
                _toggleTile(
                  isDark,
                  'DND',
                  Icons.do_not_disturb_alt_rounded,
                  AppColors.danger,
                  'dnd',
                  _toggle('toggle_dnd', 'dnd'),
                ),
                _toggleTile(
                  isDark,
                  'Auto Rotate',
                  Icons.screen_rotation_rounded,
                  AppColors.cyan,
                  'auto_rotate',
                  _toggle('set_auto_rotate', 'auto_rotate'),
                ),
                _toggleTile(
                  isDark,
                  'Flashlight',
                  Icons.flashlight_on_rounded,
                  AppColors.warning,
                  'flashlight',
                  () async {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Flashlight needs an extra permission on this build. '
                            'Ask the AI agent to try it, or enable it in Quick Settings.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionLabel('Command Deck', isDark),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 12,
                    color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'One-tap actions using the exact same pipeline the AI agent uses',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            isDark ? AppColors.darkMuted : AppColors.lightMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 3.1,
              children: [
                _actionTile(
                  isDark,
                  Icons.volume_up_rounded,
                  'Volume +10',
                  AppColors.orange,
                  () => _run(_a('set_volume', {'level': 60})),
                ),
                _actionTile(
                  isDark,
                  Icons.volume_off_rounded,
                  'Mute',
                  AppColors.danger,
                  () => _run(_a('set_volume', {'level': 0})),
                ),
                _actionTile(
                  isDark,
                  Icons.brightness_high_rounded,
                  'Brightness +20',
                  AppColors.warning,
                  () => _run(_a('set_brightness', {'level': 70})),
                ),
                _actionTile(
                  isDark,
                  Icons.brightness_low_rounded,
                  'Dim Screen',
                  AppColors.warning,
                  () => _run(_a('set_brightness', {'level': 20})),
                ),
                _actionTile(
                  isDark,
                  Icons.play_arrow_rounded,
                  'Play / Pause',
                  AppColors.success,
                  () => _run(_a('control_media', {'command': 'play'})),
                ),
                _actionTile(
                  isDark,
                  Icons.skip_next_rounded,
                  'Next Track',
                  AppColors.success,
                  () => _run(_a('control_media', {'command': 'next'})),
                ),
                _actionTile(
                  isDark,
                  Icons.light_mode_rounded,
                  'Ringer: Normal',
                  AppColors.info,
                  () => _run(_a('set_ringer_mode', {'mode': 2})),
                ),
                _actionTile(
                  isDark,
                  Icons.vibration_rounded,
                  'Ringer: Vibrate',
                  AppColors.info,
                  () => _run(_a('set_ringer_mode', {'mode': 1})),
                ),
                _actionTile(
                  isDark,
                  Icons.volume_mute_rounded,
                  'Ringer: Silent',
                  AppColors.info,
                  () => _run(_a('set_ringer_mode', {'mode': 0})),
                ),
                _actionTile(
                  isDark,
                  Icons.wb_sunny_rounded,
                  'Wake Screen',
                  AppColors.cyan,
                  () => _run(_a('wake_screen', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.lock_rounded,
                  'Lock Device',
                  AppColors.danger,
                  () => _run(_a('lock_screen', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.screenshot_rounded,
                  'Screenshot',
                  AppColors.violet,
                  () => _run(_a('take_screenshot', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.home_rounded,
                  'Go Home',
                  AppColors.indigo,
                  () => _run(_a('go_home', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.apps_rounded,
                  'Recent Apps',
                  AppColors.indigo,
                  () => _run(_a('open_recent_apps', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.notifications_off_rounded,
                  'Clear Notifs',
                  AppColors.purple,
                  () => _run(_a('clear_notifications', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.search_rounded,
                  'Scan WiFi',
                  AppColors.info,
                  () => _run(_a('scan_wifi', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.phone_android_rounded,
                  'Device Info',
                  AppColors.indigo,
                  () => _run(_a('get_device_info', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.battery_full_rounded,
                  'Battery',
                  AppColors.success,
                  () => _run(_a('get_battery', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.apps_rounded,
                  'Open App',
                  AppColors.violet,
                  () => _promptAndRun('App name to open:', 'WhatsApp',
                      (v) => _a('open_app', {'app_name': v})),
                ),
                _actionTile(
                  isDark,
                  Icons.wifi_find_rounded,
                  'Auto Connect',
                  AppColors.info,
                  () => _run(_a('connect_available_wifi', {})),
                ),
                _actionTile(
                  isDark,
                  Icons.key_rounded,
                  'Recover WiFi Pass',
                  AppColors.warning,
                  () => _promptAndRun('Network SSID to recover:', 'HomeNet',
                      (v) => _a('reveal_wifi_password', {'ssid': v})),
                ),
                _actionTile(
                  isDark,
                  Icons.admin_panel_settings_rounded,
                  'Setup Shizuku',
                  AppColors.violet,
                  () async {
                    HapticFeedback.mediumImpact();
                    setState(() => _busy = true);
                    final result =
                        await widget.actionHandler.shizuku.setupShizukuViaRoot();
                    if (!mounted) return;
                    setState(() => _busy = false);
                    _status = result.split('\n').join(' ');
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(result),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                  },
                ),
                _actionTile(
                  isDark,
                  Icons.add_alarm_rounded,
                  'Schedule Action',
                  AppColors.cyan,
                  _scheduleAction,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  AgentAction _a(String action, Map<String, dynamic> params) {
    return AgentAction(action: action, params: params, response: '');
  }

  VoidCallback _toggle(String action, String key) {
    return () => _run(
          _a(action, {'enable': !(_toggles[key] ?? false)}),
        ).then((_) {
          if (mounted) {
            setState(() {
              _toggles[key] = !(_toggles[key] ?? false);
            });
          }
        });
  }

  Widget _statusBanner(bool isDark) {
    final ok = _shizukuOk;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            tooltip: 'Re-check Shizuku',
            onPressed: _checkShizuku,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
      ),
    );
  }

  Widget _toggleTile(
    bool isDark,
    String label,
    IconData icon,
    Color color,
    String key,
    VoidCallback onTap,
  ) {
    final on = _toggles[key] ?? false;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: on ? color.withValues(alpha: 0.55) : border,
              width: on ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: on ? 0.18 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: on ? color : (isDark ? AppColors.darkMuted : AppColors.lightMuted),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    bool isDark,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A canned schedule preset shown in the "Schedule Action" dialog.
class _SchedulePreset {
  final IconData icon;
  final String label;
  final String action;
  final Map<String, dynamic> params;

  const _SchedulePreset(this.icon, this.label, this.action, this.params);
}
