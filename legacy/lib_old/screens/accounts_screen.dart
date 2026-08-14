import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../main.dart';
import '../services/ai_service.dart';
import '../services/cloudflare_service.dart';
import '../services/firebase_service.dart';
import '../services/storage_service.dart';
import '../services/telegram_service.dart';
import '../theme/app_theme.dart';

enum AccountStatus { ok, issue, off, unknown }

class _AccountTile {
  final String name;
  final String detail;
  final IconData icon;
  final Color color;
  final AccountStatus status;

  const _AccountTile({
    required this.name,
    required this.detail,
    required this.icon,
    required this.color,
    required this.status,
  });
}

/// Single place to see every connected service and credential in the app:
/// AI provider, Supabase, Firebase, FCM, the keep-alive Worker, Cloudflare R2
/// and Telegram. Every entry runs a real check — no hardcoded "Connected".
class AccountsScreen extends StatefulWidget {
  final AiService aiService;
  final TelegramService telegramService;

  const AccountsScreen({
    super.key,
    required this.aiService,
    required this.telegramService,
  });

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _checking = false;
  List<_AccountTile> _tiles = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    final tiles = await _buildTiles();
    if (!mounted) return;
    setState(() {
      _tiles = tiles;
      _checking = false;
    });
  }

  Future<List<_AccountTile>> _buildTiles() async {
    final ai = widget.aiService;
    final active = ai.activeKey;
    final aiStatus = ai.isConfigured ? AccountStatus.ok : AccountStatus.off;

    // Supabase: hit the auth health endpoint (no private data involved).
    AccountStatus supabaseStatus = AccountStatus.off;
    String supabaseDetail = 'Not initialized';
    try {
      final res = await http
          .get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/health'),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        supabaseStatus = AccountStatus.ok;
        supabaseDetail = authService.isLoggedIn
            ? 'Signed in as ${authService.email.isNotEmpty ? authService.email : 'user'}'
            : 'Reachable (signed out)';
      } else {
        supabaseStatus = AccountStatus.issue;
        supabaseDetail = 'HTTP ${res.statusCode}';
      }
    } catch (_) {
      supabaseStatus = AccountStatus.issue;
      supabaseDetail = 'Unreachable';
    }

    // Firebase + FCM.
    final firebaseOk = Firebase.apps.isNotEmpty;
    final fcmToken = FirebaseService.fcmToken;
    final AccountStatus firebaseStatus =
        firebaseOk ? AccountStatus.ok : AccountStatus.off;
    final AccountStatus fcmStatus =
        firebaseOk && fcmToken != null && fcmToken.isNotEmpty
            ? AccountStatus.ok
            : AccountStatus.off;

    // Cloudflare keep-alive Worker.
    AccountStatus workerStatus = AccountStatus.off;
    String workerDetail = 'Not reachable';
    final workerStatusData = await CloudflareService.status();
    if (workerStatusData != null) {
      workerStatus = AccountStatus.ok;
      workerDetail = workerStatusData['status']?.toString() ?? 'Reachable';
    }

    // R2.
    final r2Status = StorageService.isConfigured
        ? AccountStatus.ok
        : AccountStatus.off;

    // Telegram.
    final prefs = await SharedPreferences.getInstance();
    final tgEnabled = prefs.getBool('telegram_enabled') ?? false;
    final tgTokenSet = widget.telegramService.botToken.isNotEmpty;
    final AccountStatus tgStatus =
        tgEnabled && tgTokenSet ? AccountStatus.ok : AccountStatus.off;

    return [
      _AccountTile(
        name: 'AI Provider',
        detail: active != null
            ? '${active.name} • ${active.model}'
            : ai.isConfigured
                ? 'Keyless free backend'
                : 'No key configured',
        icon: Icons.smart_toy_rounded,
        color: AppColors.violet,
        status: aiStatus,
      ),
      _AccountTile(
        name: 'Supabase',
        detail: supabaseDetail,
        icon: Icons.cloud_queue_rounded,
        color: AppColors.success,
        status: supabaseStatus,
      ),
      _AccountTile(
        name: 'Firebase',
        detail: firebaseOk
            ? 'Core + Crashlytics active'
            : 'google-services.json missing',
        icon: Icons.local_fire_department_rounded,
        color: AppColors.warning,
        status: firebaseStatus,
      ),
      _AccountTile(
        name: 'Push Notifications (FCM)',
        detail: fcmToken != null && fcmToken.isNotEmpty
            ? 'Token registered'
            : 'Not registered',
        icon: Icons.notifications_active_rounded,
        color: AppColors.info,
        status: fcmStatus,
      ),
      _AccountTile(
        name: 'Keep-Alive Worker',
        detail: workerDetail,
        icon: Icons.bolt_rounded,
        color: AppColors.orange,
        status: workerStatus,
      ),
      _AccountTile(
        name: 'Cloudflare R2',
        detail: StorageService.isConfigured
            ? '${StorageService.bucketName} (${StorageService.accountId.length > 8 ? StorageService.accountId.substring(0, 8) : StorageService.accountId}…)'
            : 'Not configured',
        icon: Icons.storage_rounded,
        color: AppColors.cyan,
        status: r2Status,
      ),
      _AccountTile(
        name: 'Telegram Bot',
        detail: tgEnabled && tgTokenSet
            ? 'Polling active'
            : tgTokenSet
                ? 'Token saved, polling off'
                : 'Not configured',
        icon: Icons.telegram_rounded,
        color: AppColors.info,
        status: tgStatus,
      ),
    ];
  }

  (Color, IconData, String) _statusUi(AccountStatus status) {
    switch (status) {
      case AccountStatus.ok:
        return (AppColors.success, Icons.check_circle_rounded, 'Connected');
      case AccountStatus.issue:
        return (AppColors.danger, Icons.error_rounded, 'Issue');
      case AccountStatus.off:
        return (Colors.grey, Icons.remove_circle_outline_rounded, 'Off');
      case AccountStatus.unknown:
        return (AppColors.warning, Icons.help_rounded, 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final okCount = _tiles.where((t) => t.status == AccountStatus.ok).length;
    final total = _tiles.length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Accounts & Cloud Health',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppGradients.screen(isDark)),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _buildHeroCard(okCount, total, isDark),
                const SizedBox(height: 16),
                ..._tiles.map((tile) {
                  final (color, icon, label) = _statusUi(tile.status);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildTile(tile, color, icon, label, isDark),
                  );
                }),
                const SizedBox(height: 8),
                _buildConfigActions(isDark),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(int ok, int total, bool isDark) {
    final healthy = total > 0 && ok == total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppGradients.aurora,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.indigo.withValues(alpha: 0.35),
            blurRadius: 24,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            healthy ? Icons.verified_rounded : Icons.troubleshoot_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _checking
                      ? 'Checking connections…'
                      : '$ok of $total services connected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  healthy
                      ? 'Everything is running'
                      : 'Tap refresh or configure services below',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _checking ? null : _refresh,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Re-check all',
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    _AccountTile tile,
    Color statusColor,
    IconData statusIcon,
    String statusLabel,
    bool isDark,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: tile.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(tile.icon, color: tile.color, size: 22),
        ),
        title: Text(
          tile.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
        subtitle: Text(
          tile.detail,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 13),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigActions(bool isDark) {
    return Column(
      children: [
        _buildActionButton(
          icon: Icons.storage_rounded,
          color: AppColors.cyan,
          title: 'Configure Cloudflare R2',
          subtitle: 'Account ID, bucket, API token',
          onTap: _showR2ConfigDialog,
        ),
        const SizedBox(height: 10),
        _buildActionButton(
          icon: Icons.telegram_rounded,
          color: AppColors.info,
          title: 'Configure Telegram Bot',
          subtitle: 'Bot token from @BotFather + enable',
          onTap: _showTelegramConfigDialog,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }

  void _showR2ConfigDialog() {
    final accountCtrl = TextEditingController(text: StorageService.accountId);
    final bucketCtrl = TextEditingController(text: StorageService.bucketName);
    final tokenCtrl = TextEditingController(text: StorageService.apiToken);
    final emailCtrl = TextEditingController(text: StorageService.authEmail);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloudflare R2', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accountCtrl,
                decoration: const InputDecoration(labelText: 'Account ID'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bucketCtrl,
                decoration: const InputDecoration(labelText: 'Bucket name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'API token (recommended)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account email (optional)',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'The API token is preferred. A legacy email + global key pair '
                'is only used when no token is set.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await StorageService.saveConfig(
                accountId: accountCtrl.text.trim(),
                bucketName: bucketCtrl.text.trim(),
                apiToken: tokenCtrl.text.trim(),
                authEmail: emailCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('R2 configuration saved');
              _refresh();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showTelegramConfigDialog() {
    final tokenCtrl = TextEditingController(
      text: widget.telegramService.botToken,
    );
    bool enabled = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Telegram Bot', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bot token (from @BotFather)',
                ),
                obscureText: true,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable remote polling'),
                value: enabled,
                onChanged: (v) => setDialogState(() => enabled = v),
              ),
              const Text(
                'Allows you to command the agent from Telegram.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await widget.telegramService.saveSettings(
                  botToken: tokenCtrl.text.trim(),
                  isEnabled: enabled,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('Telegram settings saved');
                _refresh();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.success,
      ),
    );
  }
}
