import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config/feature_flags.dart';
import '../utils/app_info.dart';
import '../utils/device_profile.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../services/ai_service.dart';
import '../services/backup_service.dart';
import '../services/cloudflare_service.dart';
import '../services/retention_service.dart';
import '../services/chat_history_service.dart';
import '../services/firebase_service.dart';
import '../services/shizuku_service.dart';
import '../services/screen_automation_service.dart';
import '../services/telegram_service.dart';
import '../services/storage_service.dart';
import '../services/scheduler_service.dart';
import '../services/local_llm_service.dart';
import '../models/api_key_config.dart';
import 'task_history_screen.dart';
import 'accounts_screen.dart';
import 'login_screen.dart';
import 'app_lock_screen.dart';
import 'about_screen.dart';
import 'permissions_screen.dart';
import 'memory_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class SettingsScreen extends StatefulWidget {
  final AiService aiService;
  final ShizukuService shizukuService;
  final ScreenAutomationService screenAutomationService;
  final TelegramService telegramService;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.shizukuService,
    required this.screenAutomationService,
    required this.telegramService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AuthService _authService;
  bool _autoReadTts = true;
  double _ttsSpeechRate = 0.5;
  double _ttsPitch = 1.0;
  bool _isOverlayPermissionGranted = false;
  bool _floatingIconEnabled = false;
  List<String> _liveModels = [];
  bool _isFetchingModels = false;
  bool _isSyncingKeys = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isCleaning = false;
  bool _autoBackup = true;
  int _retentionDays = 30;
  bool _appLockEnabled = false;
  bool _biometricsEnabled = false;
  String _visualEffectsMode = 'auto';
  final FlutterTts _testTts = FlutterTts();
  bool _ttsBusy = false;
  int _settingsTab = 0;

  @override
  void initState() {
    super.initState();
    _authService = authService;
    _loadVoiceSettings();
    _checkOverlayPermission();
  }

  Future<void> _loadVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final appLockEnabled = await AppLockService.isEnabled();
    final biometricsEnabled = await AppLockService.isBiometricsEnabled();
    if (mounted) {
      setState(() {
        _autoReadTts = prefs.getBool('auto_read_tts') ?? true;
        _ttsSpeechRate = prefs.getDouble('tts_speech_rate') ?? 1.0;
        _ttsPitch = prefs.getDouble('tts_pitch') ?? 1.0;
        _liveModels = widget.aiService.cachedModels;
        _floatingIconEnabled = prefs.getBool('floating_icon_enabled') ?? true;
        _autoBackup = prefs.getBool('auto_backup_enabled') ?? true;
        _retentionDays = prefs.getInt(RetentionService.retentionDaysKey) ?? 30;
        _appLockEnabled = appLockEnabled;
        _biometricsEnabled = biometricsEnabled;
        _visualEffectsMode =
            prefs.getString(DeviceProfile.prefVisualEffects) ?? 'auto';
      });
    }
  }

  Future<void> _saveVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_read_tts', _autoReadTts);
    await prefs.setDouble('tts_speech_rate', _ttsSpeechRate);
    await prefs.setDouble('tts_pitch', _ttsPitch);
  }

  /// Plays a short sample using the current speech rate and pitch so the user
  /// can hear the voice settings before saving them.
  Future<void> _testVoice() async {
    if (_ttsBusy) return;
    _ttsBusy = true;
    try {
      await _testTts.stop();
      await _testTts.setVolume(1.0);
      await _testTts.setSpeechRate(_ttsSpeechRate);
      await _testTts.setPitch(_ttsPitch);
      await _testTts.speak(
        'Hello! I am your AI agent. My voice settings are working perfectly.',
      );
    } catch (_) {}
    _ttsBusy = false;
  }

  Future<void> _checkOverlayPermission() async {
    try {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (mounted) {
        setState(() => _isOverlayPermissionGranted = granted);
      }
    } catch (_) {}
  }

  Future<void> _syncCloudKeys() async {
    if (_authService.userId == null) return;
    setState(() => _isSyncingKeys = true);
    await widget.aiService.loadKeysFromSupabase(_authService.userId!);
    if (mounted) {
      setState(() => _isSyncingKeys = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ API Keys auto-synced with Supabase cloud'),
          backgroundColor: Color(0xFF2FBF8F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _fetchLiveModels() async {
    setState(() => _isFetchingModels = true);
    final models = await widget.aiService.fetchLiveModels();
    if (mounted) {
      setState(() {
        _liveModels = models;
        _isFetchingModels = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgGradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFF0A0E1A), Color(0xFF131B2E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0xFFFFFBF4), Color(0xFFF0E3D3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: IndexedStack(
            index: _settingsTab,
            children: [
              // ── AI & Keys ──────────────────────────────────────────────
              _buildTabList([
                _buildAccountCard(isDark),
                _buildAutoBackupStatusCard(isDark),
                _buildAiProviderCard(isDark),
              ]),

              // ── Voice & Agent ──────────────────────────────────────────
              _buildTabList([
                _buildVoiceSettingsCard(isDark),
                _buildOfflineAiCard(isDark),
                _buildDeviceAuthorityCard(isDark),
              ]),

              // ── Privacy & Access ───────────────────────────────────────
              _buildTabList([
                _buildSecurityCard(isDark),
                _buildPermissionsCard(isDark),
                _buildPreferencesCard(isDark),
              ]),

              // ── About & App ────────────────────────────────────────────
              _buildTabList([
                _buildAboutCard(isDark),
                _buildAdvancedSection(isDark),
              ]),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _settingsTab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _settingsTab = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy_rounded),
            label: 'AI & Keys',
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over_rounded),
            label: 'Voice & Agent',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield_rounded),
            label: 'Privacy',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline_rounded),
            selectedIcon: Icon(Icons.info_rounded),
            label: 'About',
          ),
        ],
      ),
    );
  }

  /// Wraps a list of cards into a scrollable tab with even spacing.
  Widget _buildTabList(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  /// Compact always-visible status for the automated cloud backup.
  Widget _buildAutoBackupStatusCard(bool isDark) {
    final loggedIn = _authService.isLoggedIn;
    final accent = const Color(0xFF2FBF8F);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                loggedIn ? Icons.cloud_done_rounded : Icons.cloud_outlined,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Automatic cloud backup',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loggedIn
                        ? 'ON — every API key and AI setting syncs to your '
                            'private Supabase account automatically, in the '
                            'background.'
                        : 'Sign in to back up your API keys to the cloud '
                            'automatically.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: loggedIn ? _openAccounts : _openLogin,
              icon: Icon(
                loggedIn ? Icons.chevron_right_rounded : Icons.login_rounded,
                color: accent,
              ),
              tooltip: loggedIn ? 'Manage account' : 'Sign in',
            ),
          ],
        ),
      ),
    );
  }

  /// Advanced/developer controls hidden from normal users.
  Widget _buildAdvancedSection(bool isDark) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.tune_rounded),
        title: const Text('Advanced', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text(
          'Cloud health, backup & restore, scheduled tasks, developer tools',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _buildAccountsHealthCard(isDark),
          const SizedBox(height: 12),
          _buildCloudStorageCard(isDark),
          const SizedBox(height: 12),
          _buildBackupCard(isDark),
          const SizedBox(height: 12),
          const _ScheduledTasksCard(),
        ],
      ),
    );
  }

  Widget _buildAccountCard(bool isDark) {
    final email = _authService.email.isNotEmpty ? _authService.email : 'Guest Device User';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A5C), Color(0xFFF65E8B)],
                    ),
                  ),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2FBF8F).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2FBF8F).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.cloud_done_rounded, color: Color(0xFF2FBF8F), size: 12),
                            SizedBox(width: 4),
                            Text(
                              'Auto-Synced with Supabase',
                              style: TextStyle(
                                color: Color(0xFF2FBF8F),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSyncingKeys ? null : _syncCloudKeys,
                    icon: _isSyncingKeys
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: const Text('Sync Keys'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _authService.signOut();
                      if (mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.redAccent),
                    label: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsHealthCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.troubleshoot_rounded, color: Color(0xFFFFB86B), size: 20),
                SizedBox(width: 8),
                Text(
                  'Accounts & Cloud Health',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Live status for every connected service: AI provider, Supabase, '
              'Firebase, FCM, keep-alive Worker, R2 and Telegram.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
            ),
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openAccounts,
                icon: const Icon(Icons.health_and_safety_rounded, size: 18),
                label: const Text('Open Accounts & Health'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.shield_rounded, color: Color(0xFF34D399), size: 20),
                SizedBox(width: 8),
                Text(
                  'Security & Privacy',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('App Lock (PIN)'),
              subtitle: Text(
                _appLockEnabled
                    ? 'App locks when backgrounded'
                    : 'Protect chats & keys with a 6-digit PIN',
              ),
              value: _appLockEnabled,
              onChanged: _toggleAppLock,
            ),
            if (_appLockEnabled) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unlock with fingerprint'),
                subtitle: const Text('Faster unlock using biometrics'),
                value: _biometricsEnabled,
                onChanged: (val) async {
                  setState(() => _biometricsEnabled = val);
                  await AppLockService.setBiometricsEnabled(val);
                },
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.password_rounded, color: Color(0xFF34D399)),
                title: const Text('Change PIN'),
                subtitle: const Text('Set a new 6-digit unlock code'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _changePin,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Your PIN is stored as a salted SHA-256 hash on this device only. '
              'Use a code you will remember.',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAccounts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountsScreen(
          aiService: widget.aiService,
          telegramService: widget.telegramService,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen(authService: _authService)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleAppLock(bool value) async {
    if (value) {
      // Enabling → run the setup flow (enter + confirm a new PIN).
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AppLockScreen(setupMode: true)),
      );
      if (saved == true && mounted) {
        setState(() => _appLockEnabled = true);
      }
      return;
    }
    // Disabling → require the current PIN first.
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AppLockScreen()),
    );
    if (verified == true && mounted) {
      await AppLockService.disable();
      setState(() => _appLockEnabled = false);
    }
  }

  Future<void> _changePin() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AppLockScreen(setupMode: true)),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN updated successfully')),
      );
    }
  }

  Widget _buildAiProviderCard(bool isDark) {
    final activeKey = widget.aiService.activeKey;
    final allKeys = widget.aiService.allKeys;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.smart_toy_rounded, color: Color(0xFFFF9A6B), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'AI Provider & API Keys',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFFF9A6B)),
                  onPressed: _showAddKeyModal,
                  tooltip: 'Add API Key',
                ),
              ],
            ),
            const Divider(height: 20),

            // Active Provider Display
            if (activeKey != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B4A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF6B4A).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, color: Color(0xFFFF9A6B), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeKey.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          Text(
                            'Model: ${widget.aiService.model}',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _isFetchingModels
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      onPressed: _fetchLiveModels,
                      tooltip: 'Refresh Models',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Model Selection Dropdown
            if (_liveModels.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _liveModels.contains(widget.aiService.model) ? widget.aiService.model : null,
                decoration: InputDecoration(
                  labelText: 'Select Active Model',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _liveModels.map((m) {
                  return DropdownMenuItem<String>(
                    value: m,
                    child: Text(m, style: const TextStyle(fontSize: 12.5)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    widget.aiService.saveSettings(
                      apiKey: widget.aiService.apiKey,
                      baseUrl: widget.aiService.baseUrl,
                      model: val,
                    );
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 12),
            ],

            // Saved Keys List
            const Text('Saved Keys:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ...allKeys.map((key) {
              final isActive = key.id == activeKey?.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF2FBF8F).withValues(alpha: 0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive ? const Color(0xFF2FBF8F).withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isActive ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isActive ? const Color(0xFF2FBF8F) : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await widget.aiService.setActiveApiKey(key.id);
                          setState(() {});
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(key.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              key.baseUrl,
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                      onPressed: () async {
                        await widget.aiService.deleteApiKey(key.id);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSettingsCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.record_voice_over_rounded, color: Color(0xFF2FBF8F), size: 20),
                SizedBox(width: 8),
                Text('Voice & Multilingual Speech', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Read Voice Responses'),
              subtitle: const Text('AI automatically speaks responses aloud'),
              value: _autoReadTts,
              onChanged: (val) {
                setState(() => _autoReadTts = val);
                _saveVoiceSettings();
              },
            ),

            const SizedBox(height: 8),
            Text('Speech Rate (${_ttsSpeechRate.toStringAsFixed(2)}x)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Slider(
              value: _ttsSpeechRate,
              min: 0.3,
              max: 2.0,
              divisions: 17,
              activeColor: const Color(0xFF2FBF8F),
              onChanged: (val) {
                setState(() => _ttsSpeechRate = val);
                _saveVoiceSettings();
              },
            ),

            Text('Voice Pitch (${_ttsPitch.toStringAsFixed(2)})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Slider(
              value: _ttsPitch,
              min: 0.5,
              max: 1.5,
              divisions: 10,
              activeColor: const Color(0xFF2FBF8F),
              onChanged: (val) {
                setState(() => _ttsPitch = val);
                _saveVoiceSettings();
              },
            ),

            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _testVoice,
                icon: const Icon(Icons.volume_up_rounded, size: 18),
                label: const Text('Test Voice'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2FBF8F),
                  backgroundColor: const Color(0xFF2FBF8F).withValues(alpha: 0.08),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF2FBF8F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Text('🇧🇩 🇺🇸 🇮🇳 🇸🇦', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Multilingual Bangla, English, Hindi & Auto-detect Language Engine Active',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudStorageCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.cloud_sync_rounded, color: Color(0xFF00E5FF), size: 20),
                SizedBox(width: 8),
                Text('Triple Cloud Storage Backends', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'All heavy files & data automatically backed up across 3 clouds with zero setup.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
            ),
            const Divider(height: 20),

            _buildCloudStatusItem(
              'Cloudflare R2 Storage',
              'aaa-r2 bucket',
              const Color(0xFFF97316),
              status: StorageService.isConfigured ? 'Configured' : 'Off',
            ),
            const SizedBox(height: 8),
            _buildCloudStatusItem(
              'Supabase Storage',
              'aaa-backups bucket',
              const Color(0xFF2FBF8F),
              status: _authService.isLoggedIn ? 'Synced' : 'Signed out',
            ),
            const SizedBox(height: 8),
            _buildCloudStatusItem(
              'Firebase Storage',
              'aaa-infinity-ai bucket',
              const Color(0xFFF59E0B),
              status: Firebase.apps.isNotEmpty ? 'Active' : 'Not set up',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.backup_rounded, color: Color(0xFFFF6B4A), size: 20),
                SizedBox(width: 8),
                Text('Backup & Keep-Alive', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Chats mirror to Firebase, JSON exports go to R2 + Supabase + '
              'Firebase Storage, and a Cloudflare Worker keeps Supabase awake '
              '24/7 and snapshots the database to R2 daily.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
            ),
            const Divider(height: 20),

            _buildCloudStatusItem(
              'Cloudflare Worker',
              'keepalive + daily DB snapshot',
              const Color(0xFFF97316),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isBackingUp ? null : _runBackup,
                    icon: _isBackingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(_isBackingUp ? 'Backing up…' : 'Backup Now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isRestoring ? null : _restoreFromCloud,
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: Text(_isRestoring ? 'Restoring…' : 'Restore'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Auto-backup on chat save',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              subtitle: const Text(
                'Mirror every chat session to Firestore automatically',
                style: TextStyle(fontSize: 11),
              ),
              value: _autoBackup,
              onChanged: _toggleAutoBackup,
            ),
            const SizedBox(height: 4),
            Text(
              'Automated cleanup: the Worker deletes R2 DB snapshots older '
              'than 30 days on its daily schedule.',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _isCleaning ? null : _runCleanup,
                icon: _isCleaning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_rounded, size: 18),
                label: Text(_isCleaning ? 'Cleaning…' : 'Clean old backups'),
              ),
            ),
            const Divider(height: 24),
            Text(
              'Auto-delete old chat history',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Sessions older than the window are deleted from this device, '
              'Supabase and the Firebase mirror automatically.',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final option in const [
                  (label: '7 days', days: 7),
                  (label: '30 days', days: 30),
                  (label: '90 days', days: 90),
                  (label: 'Keep all', days: 0),
                ])
                  ChoiceChip(
                    label: Text(option.label, style: const TextStyle(fontSize: 12)),
                    selected: _retentionDays == option.days,
                    onSelected: (_) => _setRetention(option.days),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runBackup() async {
    setState(() => _isBackingUp = true);
    final result = await BackupService.backupNow(userId: _authService.userId);
    if (!mounted) return;
    setState(() => _isBackingUp = false);

    final firestoreOk = result['firestore'] == true;
    final fileOk = result['file'] is String;
    final dbOk = result['db_snapshot'] is String;
    final msg = firestoreOk && fileOk
        ? 'Backup complete: Firestore ✓ R2/Supabase/Firebase ✓'
        : dbOk
            ? 'Backup saved to cloud (partial)'
            : 'Backup failed — check cloud credentials';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: fileOk ? const Color(0xFF2FBF8F) : const Color(0xFFFF4D5E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _restoreFromCloud() async {
    setState(() => _isRestoring = true);
    final restored = await BackupService.restoreFromCloud();
    if (!mounted) return;
    setState(() => _isRestoring = false);

    final msg = restored < 0
        ? 'No cloud backup found'
        : restored == 0
            ? 'Backup was empty — nothing restored'
            : 'Restored $restored chat session(s)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: restored >= 0 ? const Color(0xFF2FBF8F) : const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runCleanup() async {
    setState(() => _isCleaning = true);
    final result = await CloudflareService.triggerCleanup();
    if (!mounted) return;
    setState(() => _isCleaning = false);

    final deleted = result?['deleted'];
    final msg = deleted is int
        ? 'Cleanup done: $deleted expired snapshot(s) removed'
        : 'Cleanup failed — check worker status';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: deleted is int ? const Color(0xFF2FBF8F) : const Color(0xFFFF4D5E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setRetention(int days) async {
    setState(() => _retentionDays = days);
    await RetentionService.setRetentionDays(days);
  }

  Future<void> _toggleAutoBackup(bool value) async {
    setState(() => _autoBackup = value);
    await BackupService.setAutoBackupEnabled(value);
    final uid = _authService.userId;
    if (value && uid != null) {
      final sessions = await ChatHistoryService.loadSessions();
      await FirebaseService.backupChatsToFirestore(uid, sessions);
    }
  }

  Widget _buildCloudStatusItem(
    String title,
    String subtitle,
    Color color, {
    String status = 'Connected',
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle_rounded, color: color, size: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.shield_outlined, color: Color(0xFF2FBF8F), size: 20),
                SizedBox(width: 8),
                Text('App Permissions & Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),
            Text(
              'Microphone, screen control, overlay bubble, notifications, '
              'contacts, calls, SMS and Shizuku — check each one and grant '
              'anything that is missing.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? const Color(0xFFA8938C) : const Color(0xFF6B5A52),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PermissionsScreen(
                        shizukuService: widget.shizukuService,
                        screenAutomationService: widget.screenAutomationService,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.security_rounded, size: 18),
                label: const Text('Manage permissions'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceAuthorityCard(bool isDark) {
    final shizukuActive = widget.shizukuService.isAvailable;
    final rootActive = widget.shizukuService.isRootAvailable;
    final authorityActive = shizukuActive || rootActive;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.developer_mode_rounded, color: Color(0xFFEC4899), size: 20),
                SizedBox(width: 8),
                Text('Device Automation & Authority', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),

            // Shizuku Status
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                authorityActive ? Icons.verified_user_rounded : Icons.gavel_rounded,
                color: authorityActive ? const Color(0xFF2FBF8F) : Colors.orangeAccent,
              ),
              title: const Text('Shizuku System Authority'),
              subtitle: Text(
                shizukuActive
                    ? 'Connected with elevated ADB permissions'
                    : rootActive
                        ? 'Shizuku not running — using ROOT fallback'
                        : 'Not running — Using standard non-root intent controls',
              ),
              trailing: ElevatedButton(
                onPressed: () async {
                  await widget.shizukuService.checkAvailability();
                  setState(() {});
                },
                child: const Text('Check'),
              ),
            ),

            // Overlay Window Permission
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Floating Overlay Window'),
              subtitle: const Text('Show floating voice assistant button'),
              value: _isOverlayPermissionGranted && _floatingIconEnabled,
              onChanged: (val) async {
                if (val && !_isOverlayPermissionGranted) {
                  await FlutterOverlayWindow.requestPermission();
                  await _checkOverlayPermission();
                  if (!_isOverlayPermissionGranted) return;
                }
                setState(() => _floatingIconEnabled = val);
                FeatureFlags.floatingIconEnabled = val;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('floating_icon_enabled', val);
              },
            ),

            // Task History Link
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, color: Color(0xFFFF9A6B)),
              title: const Text('Task History Logs'),
              subtitle: const Text('View executed automation steps and logs'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TaskHistoryScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineAiCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.wifi_tethering_rounded, color: Color(0xFF2FBF8F), size: 20),
                SizedBox(width: 8),
                Text('Offline AI & Memory', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),
            FutureBuilder<bool>(
              future: SharedPreferences.getInstance()
                  .then((p) => p.getBool('use_offline_ai') ?? false),
              builder: (context, snapshot) {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Offline AI'),
                  subtitle: const Text(
                    'Real on-device AI that works with no internet or API key: '
                    'a Qwen LLM you download once inside the app, plus optional '
                    'Ollama, with an instant assistant as fallback. Auto-engages '
                    'when the network is unreachable.',
                  ),
                  value: snapshot.data ?? false,
                  onChanged: (val) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('use_offline_ai', val);
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
            const _LocalModelSection(),
            const _LocalOllamaConfig(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB86B).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.memory_rounded, size: 18, color: Color(0xFFFFB86B)),
              ),
              title: const Text('AI Memory'),
              subtitle: const Text('Facts the assistant remembers about you'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MemoryScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline_rounded, color: Color(0xFFFF8A5C), size: 20),
                SizedBox(width: 8),
                Text('About & What\u2019s New', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),
            Text(
              'Version $kAppVersion ($kAppTagline) — download a small on-device '
              'LLM (Qwen 2.5, ~470–620 MB) once inside the app and it runs fully '
              'offline, with automatic fallback when the network drops. '
              'See the full changelog.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? const Color(0xFFA8938C) : const Color(0xFF6B5A52),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Open changelog'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.palette_rounded, color: Color(0xFFFF9A6B), size: 20),
                SizedBox(width: 8),
                Text('App Preferences', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),

            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Theme',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFFF9F1EA) : const Color(0xFF2E1F1A),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.settings_brightness_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_rounded, size: 16),
                  ),
                ],
                selected: {themeNotifier.value},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  final mode = selection.first;
                  themeNotifier.value = mode;
                  SharedPreferences.getInstance().then((p) => p.setString(
                        'themeMode',
                        mode == ThemeMode.system
                            ? 'system'
                            : mode == ThemeMode.dark
                                ? 'dark'
                                : 'light',
                      ));
                },
              ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Battery-Saver Visuals'),
              subtitle: const Text(
                'Reduces background glow effects. Turns on automatically on '
                'low-RAM phones (like the Galaxy A30) for smoother chat.',
              ),
              value: _visualEffectsMode == 'off',
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  _visualEffectsMode = val ? 'off' : 'auto';
                });
                await prefs.setString(
                  DeviceProfile.prefVisualEffects,
                  val ? 'off' : 'auto',
                );
              },
            ),

            const SizedBox(height: 8),
            Center(
              child: Text(
                '$kAppName v$kAppVersion \u2022 $kAppTagline Edition',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddKeyModal() {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://openrouter.ai/api/v1');
    final modelCtrl = TextEditingController(text: 'meta-llama/llama-3.2-3b-instruct:free');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add API Key Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),

              // Provider Presets
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _presetChip('OpenRouter', 'https://openrouter.ai/api/v1', 'meta-llama/llama-3.2-3b-instruct:free', urlCtrl, modelCtrl, nameCtrl),
                    _presetChip('Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile', urlCtrl, modelCtrl, nameCtrl),
                    _presetChip('Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai/', 'gemini-1.5-flash', urlCtrl, modelCtrl, nameCtrl),
                    _presetChip('NVIDIA NIM', 'https://integrate.api.nvidia.com/v1', 'z-ai/glm-5.2', urlCtrl, modelCtrl, nameCtrl),
                    _presetChip('DeepSeek', 'https://api.deepseek.com', 'deepseek-chat', urlCtrl, modelCtrl, nameCtrl),
                    _presetChip('Puter', 'https://api.puter.com/puterai/openai/v1', 'gpt-5.4-nano', urlCtrl, modelCtrl, nameCtrl),
                    _presetChip('Ollama (on-device)', 'http://127.0.0.1:11434/v1', 'llama3.2', urlCtrl, modelCtrl, nameCtrl),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Key Label / Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'API Key', border: OutlineInputBorder()),
                obscureText: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: 'Base URL', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: 'Model Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    if (keyCtrl.text.trim().isEmpty) return;
                    final config = ApiKeyConfig(
                      id: 'key_${DateTime.now().millisecondsSinceEpoch}',
                      userId: _authService.userId ?? 'local',
                      name: nameCtrl.text.trim().isEmpty ? 'Provider Key' : nameCtrl.text.trim(),
                      provider: 'custom',
                      apiKey: keyCtrl.text.trim(),
                      baseUrl: urlCtrl.text.trim(),
                      model: modelCtrl.text.trim(),
                      isActive: true,
                    );
                    await widget.aiService.addApiKey(config);
                    if (_authService.userId != null) {
                      await widget.aiService.syncKeysToSupabase(_authService.userId!);
                    }
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      setState(() {});
                    }
                  },
                  child: const Text('Save & Activate Key', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _presetChip(String label, String url, String model, TextEditingController urlCtrl, TextEditingController modelCtrl, TextEditingController nameCtrl) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: false,
        onSelected: (_) {
          urlCtrl.text = url;
          modelCtrl.text = model;
          nameCtrl.text = label;
        },
      ),
    );
  }
}

/// Card listing active scheduled tasks with per-task cancel controls.
class _ScheduledTasksCard extends StatefulWidget {
  const _ScheduledTasksCard();

  @override
  State<_ScheduledTasksCard> createState() => _ScheduledTasksCardState();
}

class _ScheduledTasksCardState extends State<_ScheduledTasksCard> {
  Future<void> _refresh() async {
    await SchedulerService.instance.initialize();
    if (mounted) setState(() {});
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtRepeat(int minutes) {
    if (minutes <= 0) return 'Once';
    if (minutes == 30) return 'Every 30 min';
    if (minutes == 60) return 'Every hour';
    if (minutes == 360) return 'Every 6 hours';
    if (minutes == 1440) return 'Daily';
    return 'Every $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tasks = SchedulerService.instance.tasks;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_alarm_rounded,
                  size: 18,
                  color: isDark
                      ? const Color(0xFFFF9A6B)
                      : const Color(0xFFFF8A5C),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Scheduled Tasks',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The agent runs these actions automatically, even while you use other apps.',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFFA8938C)
                    : const Color(0xFF8C7A6E),
              ),
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      size: 18,
                      color: isDark
                          ? const Color(0xFF6B5A52)
                          : const Color(0xFFA8938C),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No scheduled tasks yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFFA8938C)
                            : const Color(0xFF8C7A6E),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...tasks.map((t) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF131225)
                        : const Color(0xFFFFFBF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2A2847)
                          : const Color(0xFFF0E3D3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: const Color(0xFFFFB86B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${_fmtTime(t.scheduledAt)} · ${_fmtRepeat(t.repeatMinutes)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFFA8938C)
                                    : const Color(0xFF8C7A6E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.redAccent.withValues(alpha: 0.8),
                        ),
                        tooltip: 'Cancel task',
                        onPressed: () async {
                          await SchedulerService.instance.cancel(t.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Manages the on-device AI model (Qwen 2.5 GGUF): enable toggle, model
/// choice, one-time in-app download with progress/cancel, and storage removal.
class _LocalModelSection extends StatefulWidget {
  const _LocalModelSection();

  @override
  State<_LocalModelSection> createState() => _LocalModelSectionState();
}

class _LocalModelSectionState extends State<_LocalModelSection> {
  bool _enabled = true;
  LocalModelOption? _selected;
  bool? _downloaded;
  bool _downloading = false;
  bool _cancelRequested = false;
  double _progress = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(LocalLlmService.prefEnabled) ?? true;
    final selected = await LocalLlmService.instance.selectedModel();
    final downloaded = await LocalLlmService.instance.isDownloaded(model: selected);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _selected = selected;
      _downloaded = downloaded;
    });
  }

  Future<void> _pickModel(LocalModelOption model) async {
    if (_downloading) return;
    await LocalLlmService.instance.setSelectedModel(model);
    final downloaded = await LocalLlmService.instance.isDownloaded(model: model);
    if (!mounted) return;
    setState(() {
      _selected = model;
      _downloaded = downloaded;
      _status = null;
    });
  }

  Future<void> _download() async {
    final model = _selected;
    if (model == null) return;
    setState(() {
      _downloading = true;
      _cancelRequested = false;
      _progress = 0;
      _status = null;
    });
    try {
      await LocalLlmService.instance.download(
        model,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        shouldCancel: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloaded = true;
        _status = 'Model ready. Uses RAM only while chatting.';
      });
    } catch (e) {
      if (!mounted) return;
      final cancelled = e is LocalModelCancelException;
      setState(() {
        _downloading = false;
        _status = cancelled
            ? 'Download cancelled.'
            : 'Download failed: '
                '${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  void _cancel() {
    _cancelRequested = true;
  }

  Future<void> _remove() async {
    final model = _selected;
    if (model == null) return;
    setState(() {
      _downloading = false;
      _status = null;
    });
    await LocalLlmService.instance.removeModel(model: model);
    if (!mounted) return;
    setState(() => _downloaded = false);
  }

  Future<void> _toggleEnabled(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LocalLlmService.prefEnabled, val);
    if (mounted) setState(() => _enabled = val);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor =
        isDark ? const Color(0xFFA8938C) : const Color(0xFF6B5A52);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 20),
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF2FBF8F).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.phonelink_erase_rounded,
                size: 18,
                color: Color(0xFF2FBF8F),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'On-Device AI',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text(
            'Download a small GGUF model once (Qwen 2.5, ~470–620 MB) and it '
            'runs fully offline — chat and phone actions with no internet. '
            'Loaded into RAM only while chatting, then unloads itself.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: subColor),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use on-device AI'),
          subtitle: const Text(
            'Answers offline automatically when there is no connection',
          ),
          value: _enabled,
          onChanged: _toggleEnabled,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final model in LocalLlmService.models)
                _modelTile(model, isDark, subColor),
              if (_downloading) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Downloading ${_selected?.sizeLabel ?? ''}… '
                        '${(_progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 11.5, color: subColor),
                      ),
                    ),
                    TextButton(
                      onPressed: _cancel,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ] else if (_downloaded == true)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Color(0xFF2FBF8F),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Model ready on this device',
                        style: TextStyle(fontSize: 12.5, color: subColor),
                      ),
                    ),
                    TextButton(
                      onPressed: _remove,
                      child: const Text('Remove'),
                    ),
                  ],
                )
              else if (_selected != null) ...[
                Text(
                  'Not downloaded yet — download ${_selected!.sizeLabel} once '
                  'while online to enable real offline answers.',
                  style: TextStyle(fontSize: 11.5, color: subColor),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Download model now'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(
                  _status!,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: _status!.startsWith('Model ready')
                        ? const Color(0xFF2FBF8F)
                        : const Color(0xFFFF6B4A),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _modelTile(LocalModelOption model, bool isDark, Color subColor) {
    final selected = _selected?.key == model.key;
    final ready = _downloaded == true && selected;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selected ? null : () => _pickModel(model),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: ready
                    ? const Color(0xFF2FBF8F)
                    : (selected
                        ? const Color(0xFF2FBF8F)
                        : subColor.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: subColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                model.sizeLabel,
                style: TextStyle(fontSize: 11, color: subColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Configures a real on-device/local LLM (Ollama) used by Offline AI mode.
/// Stores the base URL + model locally and can verify the connection.
class _LocalOllamaConfig extends StatefulWidget {
  const _LocalOllamaConfig();

  @override
  State<_LocalOllamaConfig> createState() => _LocalOllamaConfigState();
}

class _LocalOllamaConfigState extends State<_LocalOllamaConfig> {
  final TextEditingController _urlController = TextEditingController(
    text: 'http://127.0.0.1:11434/v1',
  );
  final TextEditingController _modelController = TextEditingController(
    text: 'llama3.2',
  );
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _urlController.text = prefs.getString('offline_llm_base_url') ??
        'http://127.0.0.1:11434/v1';
    _modelController.text =
        prefs.getString('offline_llm_model') ?? 'llama3.2';
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_llm_base_url', _urlController.text.trim());
    await prefs.setString('offline_llm_model', _modelController.text.trim());
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    await _save();
    try {
      final reply = await AiService.instance.sendToLocalEndpoint(
        'Say "Local model OK" in one short line.',
        baseUrl: _urlController.text.trim(),
        model: _modelController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = 'Connected. Model replied: ${reply.length > 40 ? '${reply.substring(0, 40)}…' : reply}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult =
            'Not reachable. Start Ollama on this phone (localhost:11434) and pull '
            'the model, then try again. (${e.toString().replaceFirst('Exception: ', '')})';
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldColor = isDark
        ? const Color(0xFF241B21)
        : const Color(0xFFF7F0E9);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'On-device model (Ollama)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFFEDE0D8) : const Color(0xFF5A4638),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: 'http://127.0.0.1:11434/v1',
              filled: true,
              fillColor: fieldColor,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              labelText: 'Model',
              hintText: 'llama3.2',
              filled: true,
              fillColor: fieldColor,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_testing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                OutlinedButton.icon(
                  onPressed: _test,
                  icon: const Icon(Icons.network_check_rounded, size: 16),
                  label: const Text('Test connection'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _testResult!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: _testResult!.startsWith('Connected')
                    ? const Color(0xFF2FBF8F)
                    : const Color(0xFFFF6B4A),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
