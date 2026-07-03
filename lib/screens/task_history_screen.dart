import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/task_history_logger.dart';

class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({super.key});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await TaskHistoryLogger.readHistory();
    final analytics = await TaskHistoryLogger.getAnalytics();
    setState(() {
      _history = history;
      _analytics = analytics;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Task History'),
        content: const Text('Are you sure you want to delete all task history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TaskHistoryLogger.clearHistory();
      _loadHistory();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Success':
        return Colors.green;
      case 'Failed':
        return Colors.red;
      case 'Cancelled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Success':
        return Icons.check_circle;
      case 'Failed':
        return Icons.cancel;
      case 'Cancelled':
        return Icons.stop_circle;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Task History (${_history.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _history.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Text('No task history found.'))
              : Column(
                  children: [
                    if (_analytics != null && _analytics!['totalTasks'] > 0)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatColumn('Total', _analytics!['totalTasks'].toString()),
                                _buildStatColumn('Success', _analytics!['successCount'].toString(), color: Colors.green),
                                _buildStatColumn('Failed', _analytics!['failedCount'].toString(), color: Colors.red),
                                _buildStatColumn('Rate', '${(_analytics!['successRate'] * 100).toStringAsFixed(1)}%'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _history.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final task = _history[index];
                          final date = DateTime.tryParse(task['timestamp'] ?? '');
                          final dateStr = date != null
                              ? DateFormat('MMM d, y h:mm a').format(date)
                              : 'Unknown Date';
                          final status = task['status'] as String? ?? 'Unknown';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: ExpansionTile(
                              leading: Icon(
                                _getStatusIcon(status),
                                color: _getStatusColor(status),
                                size: 32,
                              ),
                              title: Text(
                                task['goal'] ?? 'Unknown Goal',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    Text(dateStr, style: const TextStyle(fontSize: 12)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${task['total_tokens'] ?? 0} tokens',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              children: [
                                const Divider(),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text('Status: $status', style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      Text('Steps taken: ${task['steps_taken'] ?? 0}'),
                                      const SizedBox(height: 16),
                                      const Text('Execution Trace:', style: TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      ...((task['trace'] as List<dynamic>?) ?? []).map((t) => Padding(
                                        padding: const EdgeInsets.only(bottom: 4.0),
                                        child: Text('• $t', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                      )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatColumn(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
