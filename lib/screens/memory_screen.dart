import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/memory_service.dart';
import '../theme/app_theme.dart';

/// Manages the on-device AI memory: view, add and delete facts the assistant
/// remembers about the user across conversations.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<MemoryFact> _facts = [];
  bool _loading = true;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final facts = await MemoryService.loadFacts();
    if (!mounted) return;
    setState(() {
      _facts = facts;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final fact = await MemoryService.addFact(text);
    _controller.clear();
    await AiService.instance.reloadMemory();
    if (!mounted) return;
    setState(() => _facts.insert(0, fact));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fact saved to AI memory')),
    );
  }

  Future<void> _delete(String id) async {
    await MemoryService.removeFact(id);
    await AiService.instance.reloadMemory();
    if (!mounted) return;
    setState(() => _facts.removeWhere((f) => f.id == id));
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all memory?'),
        content: const Text(
          'This removes every fact the assistant remembers about you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MemoryService.clearAll();
    await AiService.instance.reloadMemory();
    if (!mounted) return;
    setState(() => _facts = []);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? AppColors.darkMuted : AppColors.lightMuted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Memory'),
        actions: [
          if (_facts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.memory_rounded, color: AppColors.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Facts you share ("my name is Alex") are stored on this '
                          'device and used in later conversations so the assistant '
                          'remembers you.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: sub,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _add(),
                        decoration: InputDecoration(
                          hintText: 'Add a fact, e.g. I like green tea',
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkSurfaceHigh
                              : const Color(0xFFF7F0E9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _add,
                      tooltip: 'Save fact',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _facts.isEmpty
                    ? _EmptyMemory(sub)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: _facts.length,
                          itemBuilder: (context, index) {
                            final fact = _facts[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkSurface
                                      : AppColors.lightSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.indigo
                                            .withValues(alpha: 0.14),
                                      ),
                                      child: const Icon(
                                        Icons.bookmark_rounded,
                                        size: 15,
                                        color: AppColors.indigo,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        fact.text,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          height: 1.4,
                                          color: isDark
                                              ? AppColors.darkText
                                              : AppColors.lightText,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () => _delete(fact.id),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMemory extends StatelessWidget {
  final Color sub;
  const _EmptyMemory(this.sub);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_rounded, size: 48, color: sub.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'Nothing remembered yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: sub),
          ),
          const SizedBox(height: 4),
          Text(
            'Say "remember that I like dark theme" in chat,\nor add a fact above.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: sub),
          ),
        ],
      ),
    );
  }
}
