import 'package:flutter/material.dart';
import '../services/ai_service.dart';

/// Quick-switch modal for AI model providers.
class ModelPickerSheet {
  static void show(BuildContext context, AiService aiService, VoidCallback onChanged) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.psychology_rounded,
                      color: Theme.of(ctx).primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Free AI Model',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Text(
                  'Current: ${aiService.model}',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              _buildOption(
                ctx, aiService, onChanged,
                icon: Icons.bolt_rounded,
                iconColor: Colors.orange,
                title: 'Groq (Llama 3.3 70B)',
                subtitle: 'Lightning fast & free',
                baseUrl: 'https://api.groq.com/openai/v1',
                model: 'llama-3.3-70b-versatile',
                switchMessage: 'Switched to Groq Llama 3.3 70B',
              ),
              _buildOption(
                ctx, aiService, onChanged,
                icon: Icons.public_rounded,
                iconColor: Colors.purple,
                title: 'OpenRouter (Llama 3.2 3B Free)',
                subtitle: 'Completely free tier',
                baseUrl: 'https://openrouter.ai/api/v1',
                model: 'meta-llama/llama-3.2-3b-instruct:free',
                switchMessage: 'Switched to OpenRouter Free',
              ),
              _buildOption(
                ctx, aiService, onChanged,
                icon: Icons.auto_awesome_rounded,
                iconColor: Colors.teal,
                title: 'Google Gemini 3.5 Flash',
                subtitle: 'Latest Gemini via Google AI Studio',
                baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
                model: 'gemini-3.5-flash',
                switchMessage: 'Switched to Gemini 3.5 Flash',
              ),
              _buildOption(
                ctx, aiService, onChanged,
                icon: Icons.memory_rounded,
                iconColor: Colors.green,
                title: 'NVIDIA NIM (GLM-5.2)',
                subtitle: 'High performance free NIM',
                baseUrl: AiService.nvidiaBaseUrl,
                model: AiService.nvidiaDefaultModel,
                switchMessage: 'Switched to NVIDIA NIM',
              ),
              _buildOption(
                ctx, aiService, onChanged,
                icon: Icons.cloud_circle_rounded,
                iconColor: Colors.blue,
                title: 'Ollama Cloud',
                subtitle: 'Remote Ollama instance',
                baseUrl: 'https://api.ollama.com/v1',
                model: 'llama3.3',
                switchMessage: 'Switched to Ollama Cloud',
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildOption(
    BuildContext context,
    AiService aiService,
    VoidCallback onChanged, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String baseUrl,
    required String model,
    required String switchMessage,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: () async {
        await aiService.saveSettings(
          apiKey: aiService.apiKey,
          baseUrl: baseUrl,
          model: model,
        );
        Navigator.pop(context);
        onChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switchMessage),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
    );
  }
}
