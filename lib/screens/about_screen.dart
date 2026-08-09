import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_info.dart';

/// About & "What's new" screen: version, mission, and the feature history of
/// the Aurora redesign so users can see what changed.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('About & What\u2019s New')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigo.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AAA Private Agent',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Version $kAppVersion \u2022 $kAppTagline',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _section('About', isDark),
          const SizedBox(height: 8),
          _card(
            isDark,
            child: Text(
              'AAA Private Agent turns your Android phone into a personal AI '
              'assistant. Chat with the agent, speak to it hands-free, or let '
              'it operate your device — reading the screen, tapping, typing and '
              'toggling settings across other apps.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _section('What\u2019s new in v4.5', isDark),
          const SizedBox(height: 8),
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _WhatNewItem(
                  icon: Icons.phonelink_erase_rounded,
                  color: AppColors.success,
                  text: 'A real on-device LLM is now bundled inside the app — '
                      'Qwen 2.5 (620 MB), fully offline, no downloads. It '
                      'answers chat and phone actions with no internet and '
                      'uses RAM only while chatting.',
                ),
                _WhatNewItem(
                  icon: Icons.wifi_off_rounded,
                  color: AppColors.warning,
                  text: 'Automatic offline fallback — if the network drops, '
                      'the built-in model answers right away, so the assistant '
                      'never goes silent.',
                ),
                _WhatNewItem(
                  icon: Icons.settings_rounded,
                  color: AppColors.info,
                  text: 'Settings now has a Built-in On-Device AI card to '
                      'prepare or remove the model and monitor its status.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _section('What\u2019s new in v4.4', isDark),
          const SizedBox(height: 8),
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _WhatNewItem(
                  icon: Icons.smart_toy_rounded,
                  color: AppColors.orange,
                  text: 'Real offline LLM — connect a local Ollama model on your '
                      'phone (no internet, no key). Offline AI falls back to the '
                      'instant assistant when no model is running.',
                ),
                _WhatNewItem(
                  icon: Icons.bug_report_rounded,
                  color: AppColors.success,
                  text: 'Crash-proof startup: every service initializes inside a '
                      'safety net so the app never gets stuck or crashes.',
                ),
                _WhatNewItem(
                  icon: Icons.apps_rounded,
                  color: AppColors.indigo,
                  text: 'New Aurora logo — warm coral/peach/rose gradient with a '
                      'white "A" monogram and amber spark, adaptive + monochrome.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _section('What\u2019s new in v4.3', isDark),
          const SizedBox(height: 8),
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _WhatNewItem(
                  icon: Icons.wifi_tethering_rounded,
                  color: AppColors.success,
                  text: 'Offline AI Assistant — full on-device phone control and '
                      'chat with no API key or internet. Turn it on in Settings.',
                ),
                _WhatNewItem(
                  icon: Icons.memory_rounded,
                  color: AppColors.warning,
                  text: 'AI Memory — the assistant remembers facts about you '
                      '("my name is Alex") across conversations.',
                ),
                _WhatNewItem(
                  icon: Icons.auto_awesome_rounded,
                  color: AppColors.info,
                  text: 'Free AI as the default first-open provider — no key '
                      'required to start chatting.',
                ),
                _WhatNewItem(
                  icon: Icons.share_rounded,
                  color: AppColors.purple,
                  text: 'Share any message to other apps from the long-press menu.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _section('What\u2019s new in v4.0', isDark),
          const SizedBox(height: 8),
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _WhatNewItem(
                  icon: Icons.palette_rounded,
                  color: AppColors.indigo,
                  text: 'Aurora redesign — a warm coral/peach/amber look applied '
                      'to every screen.',
                ),
                _WhatNewItem(
                  icon: Icons.explore_rounded,
                  color: AppColors.warning,
                  text: 'Discover Capabilities hub to browse every feature in one place.',
                ),
                _WhatNewItem(
                  icon: Icons.security_rounded,
                  color: AppColors.success,
                  text: 'App Permissions dashboard with live status and one-tap grant.',
                ),
                _WhatNewItem(
                  icon: Icons.add_circle_outline_rounded,
                  color: AppColors.purple,
                  text: 'Custom Quick Commands — pin your own request chips.',
                ),
                _WhatNewItem(
                  icon: Icons.tune_rounded,
                  color: AppColors.info,
                  text: 'Cleaner navigation: 4 icon actions and a grouped drawer.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _section('Recent features', isDark),
          const SizedBox(height: 8),
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _WhatNewItem(
                  icon: Icons.edit_note_rounded,
                  color: AppColors.orange,
                  text: 'Rewrite or Translate any message with AI (11 languages).',
                ),
                _WhatNewItem(
                  icon: Icons.search_rounded,
                  color: AppColors.teal,
                  text: 'Conversation search with jump-to-highlight.',
                ),
                _WhatNewItem(
                  icon: Icons.ios_share_rounded,
                  color: AppColors.info,
                  text: 'Export chats as Markdown or JSON.',
                ),
                _WhatNewItem(
                  icon: Icons.schedule_rounded,
                  color: AppColors.indigo,
                  text: 'Scheduled Tasks — run any action on a timer or repeat.',
                ),
                _WhatNewItem(
                  icon: Icons.wifi_password_rounded,
                  color: AppColors.warning,
                  text: 'WiFi password recovery straight from your own device.',
                ),
                _WhatNewItem(
                  icon: Icons.adb_rounded,
                  color: AppColors.success,
                  text: 'Self-setting Shizuku on rooted devices.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _card(
            isDark,
            highlight: true,
            child: Row(
              children: [
                const Icon(Icons.safety_check_rounded,
                    color: Color(0xFF2FBF8F), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your data stays yours. Conversations are stored on your '
                    'device and synced only to your own cloud accounts.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
        ),
      ),
    );
  }

  Widget _card(
    bool isDark, {
    required Widget child,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight
              ? AppColors.success.withValues(alpha: 0.4)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: highlight ? 1.4 : 1.1,
        ),
      ),
      child: child,
    );
  }
}

class _WhatNewItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _WhatNewItem({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
