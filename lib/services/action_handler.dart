import '../models/agent_action.dart';
import '../models/chat_message.dart';
import 'app_launcher_service.dart';
import 'contacts_service.dart';
import 'communication_service.dart';
import 'alarm_service.dart';
import 'system_control_service.dart';
import 'shizuku_service.dart';
import 'screen_automation_service.dart';
import 'task_executor.dart';
import 'ai_service.dart';

class ActionHandler {
  final AppLauncherService _appLauncher = AppLauncherService();
  final ContactsService _contacts = ContactsService();
  final CommunicationService _communication = CommunicationService();
  final AlarmService _alarm = AlarmService();
  final SystemControlService _systemControl = SystemControlService();
  final ShizukuService _shizuku = ShizukuService();
  final ScreenAutomationService _screenAutomation = ScreenAutomationService();

  ShizukuService get shizuku => _shizuku;
  ScreenAutomationService get screenAutomation => _screenAutomation;

  /// The currently running task executor, if any
  TaskExecutor? _currentExecutor;

  /// Execute an action and return the result
  Future<AgentActionResult> execute(
    AgentAction action, {
    AiService? aiService,
    void Function(String)? onProgress,
  }) async {
    try {
      String result;

      switch (action.action) {
        case 'open_app':
          result = await _appLauncher.openApp(
            action.params['app_name'] as String? ?? '',
          );
          break;

        case 'launch_package':
          final packageName = action.params['package_name'] as String? ?? '';
          result = await _appLauncher.openPackage(packageName);
          break;

        case 'macro_meet':
          if (onProgress != null) onProgress('Thinking...');
          await Future.delayed(const Duration(seconds: 10));

          if (onProgress != null) onProgress('Planning steps...');
          await _appLauncher.openPackage('com.google.android.apps.tachyon');
          
          // Wait for app to load
          await Future.delayed(const Duration(seconds: 5));
          if (onProgress != null) onProgress('Executing plan...');
          
          // Pull screen and tap New
          await _screenAutomation.getScreenDescription(); // purely to refresh nodes if needed
          await _screenAutomation.clickByText('New');
          
          // Wait for transition
          await Future.delayed(const Duration(seconds: 3));
          if (onProgress != null) onProgress('Taking action...');
          
          // Tap contact (try both cases just in case)
          await _screenAutomation.getScreenDescription();
          bool clicked = await _screenAutomation.clickByText('Orailnoor');
          if (!clicked) {
             await _screenAutomation.clickByText('orailnoor');
          }
          
          // Wait for transition and click Call
          await Future.delayed(const Duration(seconds: 3));
          if (onProgress != null) onProgress('Finalizing...');
          
          await _screenAutomation.getScreenDescription();
          await _screenAutomation.clickByText('Call');
          
          result = 'Setting up a Google Meet with Orailnoor.';
          break;

        case 'macro_privatelm':
          if (onProgress != null) onProgress('Thinking...');
          await Future.delayed(const Duration(seconds: 4));

          if (onProgress != null) onProgress('Opening PrivateLM...');
          final pkgName = action.params['package_name'] as String? ?? 'com.orailnoor.privatelm';
          await _appLauncher.openPackage(pkgName);

          // Wait longer for app to fully load
          await Future.delayed(const Duration(seconds: 8));
          if (onProgress != null) onProgress('Typing message...');

          await _screenAutomation.getScreenDescription();
          
          // The hint text in PrivateLM's text box is 'What can you do'
          // We click that so the field gets focus.
          await _screenAutomation.clickByText('What can you do');
          
          await Future.delayed(const Duration(seconds: 1));
          
          await _screenAutomation.typeText('What can you do');
          await Future.delayed(const Duration(seconds: 2));
          
          if (onProgress != null) onProgress('Sending message...');
          
          final nodes = await _screenAutomation.dumpScreen();
          Map<String, dynamic>? inputNode;
          for (var node in nodes) {
            String nodeText = (node['text'] ?? '').toString();
            if (nodeText.contains('What can you do')) {
              inputNode = node;
              break;
            }
          }
          
          bool clickedSend = false;
          if (inputNode != null && inputNode['bounds'] != null) {
            final bounds = inputNode['bounds'];
            final inputCenterY = (bounds['top'] + bounds['bottom']) / 2;
            
            Map<String, dynamic>? sendNode;
            double maxCenterX = -1;
            
            for (var node in nodes) {
              if (node['bounds'] == null) continue;
              if (node['index'] == inputNode['index']) continue;
              if (node['isClickable'] != true) continue;
              
              final b = node['bounds'];
              final centerY = (b['top'] + b['bottom']) / 2;
              final centerX = (b['left'] + b['right']) / 2;
              
              // Find a clickable node roughly on the same Y-axis
              if ((centerY - inputCenterY).abs() < 120) {
                // Find the rightmost one
                if (centerX > maxCenterX) {
                  maxCenterX = centerX;
                  sendNode = node;
                }
              }
            }
            
            if (sendNode != null) {
              final b = sendNode['bounds'];
              double clickX = (b['left'] + b['right']) / 2;
              double clickY = (b['top'] + b['bottom']) / 2;
              await _screenAutomation.clickAt(clickX, clickY);
              clickedSend = true;
            }
          }
          
          if (!clickedSend) {
             // Fallback to enter
             await _screenAutomation.pressEnter();
          }
          
          result = 'Opening PrivateLM and asking...';
          break;

        case 'make_call':
          result = await _communication.makeCall(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
          );
          break;

        case 'send_sms':
          result = await _communication.sendSms(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
            message: action.params['message'] as String? ?? '',
          );
          break;

        case 'search_contact':
          result = await _contacts.searchAndFormat(
            action.params['query'] as String? ?? '',
          );
          break;

        case 'set_alarm':
          result = await _alarm.setAlarm(
            hour: (action.params['hour'] as num?)?.toInt() ?? 0,
            minute: (action.params['minute'] as num?)?.toInt() ?? 0,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_timer':
          result = await _alarm.setTimer(
            seconds: (action.params['seconds'] as num?)?.toInt() ?? 60,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_volume':
          result = await _systemControl.setVolume(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'set_brightness':
          result = await _systemControl.setBrightness(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'run_adb_command':
          result = await _shizuku.runCommand(
            action.params['command'] as String? ?? '',
          );
          break;

        case 'send_email':
          result = await _communication.sendEmail(
            to: action.params['to'] as String? ?? '',
            subject: action.params['subject'] as String?,
            body: action.params['body'] as String?,
          );
          break;

        case 'open_url':
          result = await _appLauncher.openUrl(
            action.params['url'] as String? ?? '',
          );
          break;

        // ─── Screen Automation Actions ────────────────────────

        case 'read_screen':
          result = await _screenAutomation.getScreenDescription();
          break;

        case 'click_element':
          final text = action.params['text'] as String? ?? '';
          final success = await _screenAutomation.clickByText(text);
          result = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'type_on_screen':
          final text = action.params['text'] as String? ?? '';
          final hint = action.params['field_hint'] as String?;
          final success = await _screenAutomation.typeText(text, fieldHint: hint);
          result = success ? 'Typed "$text"' : 'Could not type into field';
          break;

        case 'scroll_screen':
          final direction = action.params['direction'] as String? ?? 'down';
          final success = await _screenAutomation.scroll(direction);
          result = success ? 'Scrolled $direction' : 'Could not scroll';
          break;

        case 'press_back':
          final success = await _screenAutomation.pressBack();
          result = success ? 'Pressed back' : 'Could not press back';
          break;

        // ─── Multi-Step Task Execution ────────────────────────

        case 'execute_task':
          final goal = action.params['goal'] as String? ?? action.response;
          if (aiService == null) {
            result = 'AI service not available for task execution.';
            break;
          }
          _currentExecutor = TaskExecutor(
            aiService: aiService,
            screenService: _screenAutomation,
            appLauncher: _appLauncher,
            shizukuService: _shizuku,
            onProgress: onProgress,
          );
          result = await _currentExecutor!.executeTask(goal);
          _currentExecutor = null;
          break;

        default:
          result = action.response;
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e) {
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  /// Cancel the currently running task
  void cancelTask() {
    _currentExecutor?.cancel();
  }
}
