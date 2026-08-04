import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config/feature_flags.dart';
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
import '../models/api_key_config.dart';
import 'task_history_screen.dart';
import 'accounts_screen.dart';
import 'app_lock_screen.dart';
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
    if (mounted) {
      setState(() {
        _autoReadTts = prefs.getBool('auto_read_tts') ?? true;
        _ttsSpeechRate = prefs.getDouble('tts_speech_rate') ?? 0.5;
        _ttsPitch = prefs.getDouble('tts_pitch') ?? 1.0;
        _liveModels = widget.aiService.cachedModels;
        _floatingIconEnabled = prefs.getBool('floating_icon_enabled') ?? true;
        _autoBackup = prefs.getBool('auto_backup_enabled') ?? true;
        _retentionDays = prefs.getInt(RetentionService.retentionDaysKey) ?? 30;
        _appLockEnabled = appLockEnabled;
      });
    }
  }

  Future<void> _saveVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_read_tts', _autoReadTts);
    await prefs.setDouble('tts_speech_rate', _ttsSpeechRate);
    await prefs.setDouble('tts_pitch', _ttsPitch);
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
          backgroundColor: Color(0xFF10B981),
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
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
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
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. ACCOUNT & CLOUD SYNC HEADER
              _buildAccountCard(isDark),
              const SizedBox(height: 16),

              // 1b. ACCOUNTS & CLOUD HEALTH
              _buildAccountsHealthCard(isDark),
              const SizedBox(height: 16),

              // 1c. SECURITY & PRIVACY
              _buildSecurityCard(isDark),
              const SizedBox(height: 16),

              // 2. AI PROVIDER & SAVED KEYS
              _buildAiProviderCard(isDark),
              const SizedBox(height: 16),

              // 3. VOICE & MULTILINGUAL SPEECH
              _buildVoiceSettingsCard(isDark),
              const SizedBox(height: 16),

              // 4. CLOUD BACKENDS STATUS
              _buildCloudStorageCard(isDark),
              const SizedBox(height: 16),

              // 5. BACKUP & KEEP-ALIVE
              _buildBackupCard(isDark),
              const SizedBox(height: 16),

              // 6. DEVICE AUTOMATION & AUTHORITY
              _buildDeviceAuthorityCard(isDark),
              const SizedBox(height: 16),

              // 7. APP PREFERENCES & THEMING
              _buildPreferencesCard(isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),
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
                      colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
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
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.cloud_done_rounded, color: Color(0xFF10B981), size: 12),
                            SizedBox(width: 4),
                            Text(
                              'Auto-Synced with Supabase',
                              style: TextStyle(
                                color: Color(0xFF10B981),
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
                Icon(Icons.troubleshoot_rounded, color: Color(0xFF22D3EE), size: 20),
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountsScreen(
          aiService: widget.aiService,
          telegramService: widget.telegramService,
        ),
      ),
    );
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
                    Icon(Icons.smart_toy_rounded, color: Color(0xFF818CF8), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'AI Provider & API Keys',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF818CF8)),
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
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, color: Color(0xFF818CF8), size: 20),
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
                  color: isActive ? const Color(0xFF10B981).withValues(alpha: 0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive ? const Color(0xFF10B981).withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isActive ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isActive ? const Color(0xFF10B981) : Colors.grey,
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
                Icon(Icons.record_voice_over_rounded, color: Color(0xFF10B981), size: 20),
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
              min: 0.2,
              max: 1.5,
              divisions: 13,
              activeColor: const Color(0xFF10B981),
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
              activeColor: const Color(0xFF10B981),
              onChanged: (val) {
                setState(() => _ttsPitch = val);
                _saveVoiceSettings();
              },
            ),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
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
              const Color(0xFF10B981),
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
                Icon(Icons.backup_rounded, color: Color(0xFF6366F1), size: 20),
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
        backgroundColor: fileOk ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
        backgroundColor: restored >= 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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
        backgroundColor: deleted is int ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
                color: authorityActive ? const Color(0xFF10B981) : Colors.orangeAccent,
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
              leading: const Icon(Icons.history_rounded, color: Color(0xFF818CF8)),
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

  Widget _buildPreferencesCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.palette_rounded, color: Color(0xFFA78BFA), size: 20),
                SizedBox(width: 8),
                Text('App Preferences', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dark Mode'),
              subtitle: const Text('Enable obsidian dark visual theme'),
              value: isDark,
              onChanged: (val) {
                themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                SharedPreferences.getInstance().then((p) => p.setString('themeMode', val ? 'dark' : 'light'));
              },
            ),

            const SizedBox(height: 8),
            Center(
              child: Text(
                'AAA Private Agent v2.0 • Nebula Edition',
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
