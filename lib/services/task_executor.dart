import 'dart:convert';
import 'dart:developer' as developer;
import 'ai_service.dart';
import 'screen_automation_service.dart';
import 'app_launcher_service.dart';
import 'notification_service.dart';

/// Executes multi-step UI automation tasks using LLM-guided screen reading.
/// 
/// Flow: User gives high-level goal → LLM reads screen → decides next action → 
/// executes → reads screen again → repeats until goal is complete.
class TaskExecutor {
  final AiService _aiService;
  final ScreenAutomationService _screenService;
  final AppLauncherService _appLauncher;
  final NotificationService _notificationService = NotificationService();

  /// Callback to report progress messages to the UI
  final void Function(String message)? onProgress;

  TaskExecutor({
    required AiService aiService,
    required ScreenAutomationService screenService,
    required AppLauncherService appLauncher,
    this.onProgress,
  })  : _aiService = aiService,
        _screenService = screenService,
        _appLauncher = appLauncher;

  static const String _taskSystemPrompt = '''
You are a phone automation agent. You are given a TASK and the current SCREEN content.
You must decide what single action to take next to accomplish the task.

Respond with ONLY a JSON object (no markdown, no code fences):
{
  "action": "action_name",
  "params": {"key": "value"},
  "reasoning": "why you chose this action",
  "is_complete": false
}

Available actions:
- click_text: {"text": "exact text to click"} - Click an element by its visible text
- click_at: {"x": 540, "y": 960} - Click at screen coordinates (use bounds from screen dump)
- type_text: {"text": "hello", "field_hint": "optional hint"} - Type into the focused/first edit field
- scroll: {"direction": "down"} - Scroll down/up on the current view
- press_back: {} - Press the back button
- press_home: {} - Press the home button
- open_app: {"app_name": "WhatsApp"} - Open an app
- wait: {} - Wait a moment for content to load
- done: {} - Task is complete

Rules:
- You will receive a TEXT DUMP of the accessibility tree containing exact text strings and center coordinates.
- ALWAYS use the text dump to decide your next action.
- If you need to click something, prefer using `click_text`. If the element does not have text, use `click_at` with the coordinates provided in the text dump.
- When typing in a search box, you MUST click it first, wait a step, and THEN type.
- Set is_complete=true ONLY when the task is fully done.
- If you need to find something by scrolling, scroll and then check the screen again.
- If stuck after 3 attempts, set is_complete=true and explain in reasoning.
- Keep reasoning very brief (1 sentence)
''';

  /// Execute a multi-step task with LLM guidance
  Future<String> executeTask(String userGoal) async {
    final isRunning = await _screenService.isServiceRunning();
    if (!isRunning) {
      return 'Accessibility service is not enabled. Go to Settings → Accessibility → PrivateAgent Screen Control and enable it.';
    }

    final results = <String>[];
    results.add('Starting task: $userGoal');
    _report('Starting task: $userGoal');

    for (int step = 0; step < _aiService.maxSteps; step++) {
      // Small delay to let UI settle
      await Future.delayed(const Duration(milliseconds: 500));

      // 1. Read the current screen text
      final screenContent = await _screenService.getScreenDescription();
      developer.log('=== SCREEN DUMP (Step ${step + 1}) ===\n$screenContent', name: 'PrivateAgent');

      // Determine previous result string
      final prevResultStr = step > 0 && results.isNotEmpty 
          ? '\nPREVIOUS ACTION RESULT: ${results.last}\n' 
          : '';

      // 2. Ask LLM what to do next
      final prompt = step == 0
          ? '''$_taskSystemPrompt

TASK: $userGoal

CURRENT SCREEN TEXT DUMP:
$screenContent

Step ${step + 1}/${_aiService.maxSteps}. Look at the text dump and coordinates. What is the next action?'''
          : '''TASK: $userGoal

CURRENT SCREEN TEXT DUMP:
$screenContent$prevResultStr
Step ${step + 1}/${_aiService.maxSteps}. Look at the text dump and coordinates. What is the next action?''';

      developer.log('=== AI PROMPT ===\n$prompt', name: 'PrivateAgent');

      String response;
      try {
        response = await _aiService.sendMessage(prompt);
        developer.log('=== RAW AI RESPONSE ===\n$response', name: 'PrivateAgent');
      } catch (e) {
        results.add('AI error: $e');
        _report('Error: $e');
        _notificationService.showTaskCompleteNotification('Task Error', 'AI encountered an error.');
        return results.join('\n');
      }

      // 3. Parse the action
      Map<String, dynamic>? actionJson;
      try {
        String jsonStr = response.trim();
        
        // Use Regex to find the first JSON-like block (anything between { and })
        // This is robust against conversational fluff like "Here is your JSON:"
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(0)!;
        }
        
        actionJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        // LLM didn't return valid JSON
        results.add('Step ${step + 1}: Invalid JSON response');
        _report('Error: AI did not return valid JSON code.');
        _notificationService.showTaskCompleteNotification('Task Error', 'AI formatting error.');
        return results.join('\n');
      }

      final action = actionJson['action'] as String? ?? 'done';
      final params = actionJson['params'] as Map<String, dynamic>? ?? {};
      final reasoning = actionJson['reasoning'] as String? ?? '';
      final isComplete = actionJson['is_complete'] == true;

      developer.log('=== PARSED ACTION ===\nAction: $action\nParams: $params\nReasoning: $reasoning\nIs Complete: $isComplete', name: 'PrivateAgent');

      _report('Step ${step + 1}: $reasoning');

      // 4. Execute the action
      bool success = false;
      String actionResult = '';

      switch (action) {
        case 'click_text':
          final text = params['text'] as String? ?? '';
          success = await _screenService.clickByText(text);
          actionResult = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'click_at':
          final x = (params['x'] as num?)?.toDouble() ?? 0;
          final y = (params['y'] as num?)?.toDouble() ?? 0;
          success = await _screenService.clickAt(x, y);
          actionResult = success ? 'Clicked at ($x, $y)' : 'Click failed';
          break;

        case 'type_text':
          final text = params['text'] as String? ?? '';
          final hint = params['field_hint'] as String?;
          success = await _screenService.typeText(text, fieldHint: hint);
          actionResult = success ? 'Typed "$text"' : 'Could not type text';
          break;

        case 'scroll':
          final direction = params['direction'] as String? ?? 'down';
          success = await _screenService.scroll(direction);
          actionResult = success ? 'Scrolled $direction' : 'Scroll failed';
          break;

        case 'press_back':
          success = await _screenService.pressBack();
          actionResult = 'Pressed back';
          break;

        case 'press_home':
          success = await _screenService.pressHome();
          actionResult = 'Pressed home';
          break;

        case 'open_app':
          final appName = params['app_name'] as String? ?? '';
          actionResult = await _appLauncher.openApp(appName);
          success = actionResult.startsWith('Opened');
          break;

        case 'wait':
          await Future.delayed(const Duration(seconds: 1));
          actionResult = 'Waited';
          success = true;
          break;

        case 'done':
          results.add('Task complete: $reasoning');
          _report('Task complete: $reasoning');
          _notificationService.showTaskCompleteNotification('Task Completed', reasoning ?? 'Agent finished its goal.');
          return results.join('\n');

        default:
          actionResult = 'Unknown action: $action';
      }

      developer.log('=== NATIVE EXECUTION RESULT ===\n$actionResult', name: 'PrivateAgent');

      results.add('Step ${step + 1}: $actionResult ($reasoning)');

      if (isComplete) {
        results.add('Task complete.');
        _report('Task complete.');
        _notificationService.showTaskCompleteNotification('Task Completed', 'Agent finished its goal.');
        return results.join('\n');
      }
    }

    results.add('Reached maximum steps (${_aiService.maxSteps}). Task may be incomplete.');
    _report('Reached maximum steps.');
    _notificationService.showTaskCompleteNotification('Task Stopped', 'Reached maximum steps (${_aiService.maxSteps}).');
    return results.join('\n');
  }

  void _report(String message) {
    onProgress?.call(message);
  }
}
