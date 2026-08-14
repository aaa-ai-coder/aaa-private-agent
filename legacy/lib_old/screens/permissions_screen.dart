import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/notification_service.dart';
import '../services/screen_automation_service.dart';
import '../services/shizuku_service.dart';
import '../theme/app_theme.dart';

/// Permission dashboard: live status for every access the agent needs
/// (microphone, accessibility, overlay bubble, notifications, contacts,
/// phone, SMS and Shizuku) with one-tap Grant / Open-settings actions.
class PermissionsScreen extends StatefulWidget {
  final ShizukuService shizukuService;
  final ScreenAutomationService screenAutomationService;

  const PermissionsScreen({
    super.key,
    required this.shizukuService,
    required this.screenAutomationService,
  });

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _mic = false;
  bool _accessibility = false;
  bool _overlay = false;
  bool _notifications = false;
  bool _contacts = false;
  bool _phone = false;
  bool _sms = false;
  bool _shizuku = false;
  bool _batteryOpt = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);

    final mic = await Permission.microphone.status;
    final contacts = await Permission.contacts.status;
    final phone = await Permission.phone.status;
    final sms = await Permission.sms.status;
    final notifications = await Permission.notification.status;
    final batteryOpt = await Permission.ignoreBatteryOptimizations.status;
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
    final accessibility = await widget.screenAutomationService.isServiceRunning();

    await widget.shizukuService.checkAvailability();

    if (!mounted) return;
    setState(() {
      _mic = mic.isGranted;
      _contacts = contacts.isGranted;
      _phone = phone.isGranted;
      _sms = sms.isGranted;
      _notifications = notifications.isGranted;
      _overlay = overlay;
      _accessibility = accessibility;
      _shizuku = widget.shizukuService.hasPermission;
      _batteryOpt = batteryOpt.isGranted;
      _checking = false;
    });
  }

  int get _grantedCount => [
        _mic,
        _accessibility,
        _overlay,
        _notifications,
        _contacts,
        _phone,
        _sms,
        _shizuku,
        _batteryOpt,
      ].where((g) => g).length;

  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.request();
    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    _refresh();
  }

  Future<void> _requestOverlay() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
    _refresh();
  }

  Future<void> _requestAccessibility() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable Screen Control'),
        content: const Text(
          'If Android shows a "Restricted setting", open App Info first, tap the '
          'three-dot menu and choose "Allow restricted settings". Then return '
          'and toggle on PrivateAgent Screen Control in Accessibility.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('Open App Info'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              widget.screenAutomationService.openAccessibilitySettings();
            },
            child: const Text('Accessibility Settings'),
          ),
        ],
      ),
    );
    _refresh();
  }

  Future<void> _requestShizuku() async {
    await widget.shizukuService.requestPermission();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('App Permissions')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.indigo,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _summaryCard(isDark),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: _checking ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_checking ? 'Checking…' : 'Re-check status'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _sectionHeader('CORE ACCESS', isDark),
            _permissionCard(
              title: 'Screen Control',
              description:
                  'Lets the AI read your screen and perform clicks, scrolls and '
                  'typing across other apps.',
              icon: Icons.visibility_rounded,
              color: AppColors.indigo,
              granted: _accessibility,
              grantLabel: 'Enable',
              onGrant: _requestAccessibility,
            ),
            _permissionCard(
              title: 'Microphone',
              description: 'Needed for voice commands and speech-to-text.',
              icon: Icons.mic_rounded,
              color: AppColors.purple,
              granted: _mic,
              grantLabel: 'Grant',
              onGrant: () => _requestPermission(Permission.microphone),
            ),
            _permissionCard(
              title: 'Display Over Other Apps',
              description:
                  'Shows the floating bubble so you can watch and control tasks '
                  'while other apps are open.',
              icon: Icons.layers_rounded,
              color: AppColors.warning,
              granted: _overlay,
              grantLabel: 'Allow',
              onGrant: _requestOverlay,
            ),
            _permissionCard(
              title: 'Notifications',
              description:
                  'Ongoing task progress and completion alerts in the notification tray.',
              icon: Icons.notifications_rounded,
              color: AppColors.success,
              granted: _notifications,
              grantLabel: 'Grant',
              onGrant: () async {
                await NotificationService().requestPermission();
                _refresh();
              },
            ),
            const SizedBox(height: 8),
            _sectionHeader('CONTACTS & COMMS', isDark),
            _permissionCard(
              title: 'Contacts',
              description: 'Looks up names and numbers when you ask the AI to call or text.',
              icon: Icons.contacts_rounded,
              color: AppColors.info,
              granted: _contacts,
              grantLabel: 'Grant',
              onGrant: () => _requestPermission(Permission.contacts),
            ),
            _permissionCard(
              title: 'Phone',
              description: 'Lets the AI dial calls on your behalf.',
              icon: Icons.phone_rounded,
              color: AppColors.orange,
              granted: _phone,
              grantLabel: 'Grant',
              onGrant: () => _requestPermission(Permission.phone),
            ),
            _permissionCard(
              title: 'SMS',
              description: 'Sends and reads text messages on your behalf.',
              icon: Icons.sms_rounded,
              color: AppColors.danger,
              granted: _sms,
              grantLabel: 'Grant',
              onGrant: () => _requestPermission(Permission.sms),
            ),
            const SizedBox(height: 8),
            _sectionHeader('ADVANCED', isDark),
            _permissionCard(
              title: 'Shizuku',
              description:
                  'Deep device automation on rooted devices. Skip if you rely '
                  'on the Accessibility mode only.',
              icon: Icons.adb_rounded,
              color: AppColors.teal,
              granted: _shizuku,
              grantLabel: 'Grant',
              onGrant: _requestShizuku,
            ),
            _permissionCard(
              title: 'Battery Optimization',
              description:
                  'Keeps background tasks and the floating bubble alive — exempt '
                  'the agent from aggressive battery restrictions.',
              icon: Icons.battery_charging_full_rounded,
              color: AppColors.info,
              granted: _batteryOpt,
              grantLabel: 'Exempt',
              onGrant: () => _requestPermission(Permission.ignoreBatteryOptimizations),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(bool isDark) {
    final total = 9;
    final ratio = _grantedCount / total;
    final color = ratio >= 1
        ? AppColors.success
        : ratio >= 0.5
            ? AppColors.warning
            : AppColors.danger;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF241B21), Color(0xFF2E2228)]
              : const [Color(0xFFFFFBF4), Color(0xFFF7EDE0)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.1,
        ),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 6,
                  backgroundColor:
                      (isDark ? AppColors.darkBorder : AppColors.lightBorder)
                          .withValues(alpha: 0.6),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                '$_grantedCount/$total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ratio >= 1
                      ? 'All permissions granted'
                      : ratio >= 0.5
                          ? 'Almost there'
                          : 'Set up access',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ratio >= 1
                      ? 'The agent has full access to help you.'
                      : 'Grant the permissions below so the AI agent can control '
                          'your phone safely.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
        ),
      ),
    );
  }

  Widget _permissionCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required bool granted,
    required String grantLabel,
    required VoidCallback onGrant,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: granted
              ? AppColors.success.withValues(alpha: 0.35)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.lightText,
                          ),
                        ),
                      ),
                      Icon(
                        granted
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        size: 20,
                        color: granted
                            ? AppColors.success
                            : (isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark
                          ? AppColors.darkMuted
                          : AppColors.lightMuted,
                    ),
                  ),
                  if (!granted) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: onGrant,
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 34),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(grantLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
