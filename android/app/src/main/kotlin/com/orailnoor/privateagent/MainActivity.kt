package com.orailnoor.privateagent

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.graphics.PixelFormat
import android.graphics.Color
import android.view.Gravity
import android.view.WindowManager
import android.view.View
import android.widget.Button
import android.net.Uri

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.privateagent/accessibility"
    private val EVENT_CHANNEL = "com.privateagent/accessibility_events"
    private var eventSink: EventChannel.EventSink? = null
    private var overlayView: View? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    AgentAccessibilityService.eventListener = { eventMap ->
                        runOnUiThread {
                            eventSink?.success(eventMap)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    AgentAccessibilityService.eventListener = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "isServiceRunning" -> {
                        result.success(AgentAccessibilityService.isRunning())
                    }

                    "checkOverlayPermission" -> {
                        result.success(Settings.canDrawOverlays(this@MainActivity))
                    }

                    "requestOverlayPermission" -> {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }

                    "showMacroOverlay" -> {
                        if (Settings.canDrawOverlays(this@MainActivity)) {
                            if (overlayView == null) {
                                val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
                                val params = WindowManager.LayoutParams(
                                    WindowManager.LayoutParams.WRAP_CONTENT,
                                    WindowManager.LayoutParams.WRAP_CONTENT,
                                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
                                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                                    else
                                        WindowManager.LayoutParams.TYPE_PHONE,
                                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                                    PixelFormat.TRANSLUCENT
                                )
                                params.gravity = Gravity.BOTTOM or Gravity.END
                                params.x = 50
                                params.y = 200

                                val btn = Button(this@MainActivity).apply {
                                    text = "🛑 Stop Macro"
                                    setBackgroundColor(Color.RED)
                                    setTextColor(Color.WHITE)
                                    setPadding(40, 20, 40, 20)
                                    setOnClickListener {
                                        // Broadcast stop event
                                        eventSink?.success(mapOf("type" to "stop_macro"))
                                    }
                                }
                                overlayView = btn
                                windowManager.addView(overlayView, params)
                            }
                            result.success(true)
                        } else {
                            result.error("PERMISSION_DENIED", "Overlay permission not granted", null)
                        }
                    }

                    "hideMacroOverlay" -> {
                        if (overlayView != null) {
                            val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
                            windowManager.removeView(overlayView)
                            overlayView = null
                        }
                        result.success(true)
                    }

                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }

                    "dumpScreen" -> {
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            val nodes = service.dumpScreen()
                            result.success(nodes)
                        }
                    }

                    "takeScreenshot" -> {
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                service.takeScreenshot { base64 ->
                                    if (base64 != null) {
                                        result.success(base64)
                                    } else {
                                        result.error("SCREENSHOT_FAILED", "Failed to capture screenshot", null)
                                    }
                                }
                            } else {
                                result.error("UNSUPPORTED_VERSION", "Screenshot requires Android 11 (API 30) or higher", null)
                            }
                        }
                    }

                    "clickByText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.clickByText(text))
                        }
                    }

                    "clickAt" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.clickAtCoordinates(x, y))
                        }
                    }

                    "typeText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val hint = call.argument<String>("fieldHint")
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.typeText(text, hint))
                        }
                    }

                    "pressEnter" -> {
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.pressEnter())
                        }
                    }

                    "scroll" -> {
                        val direction = call.argument<String>("direction") ?: "down"
                        val target = call.argument<String>("target")
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.scroll(direction, target))
                        }
                    }

                    "showToast" -> {
                        val message = call.argument<String>("message") ?: ""
                        android.widget.Toast.makeText(this@MainActivity, message, android.widget.Toast.LENGTH_SHORT).show()
                        result.success(true)
                    }

                    "swipe" -> {
                        val startX = call.argument<Double>("startX")?.toFloat() ?: 0f
                        val startY = call.argument<Double>("startY")?.toFloat() ?: 0f
                        val endX = call.argument<Double>("endX")?.toFloat() ?: 0f
                        val endY = call.argument<Double>("endY")?.toFloat() ?: 0f
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.swipe(startX, startY, endX, endY))
                        }
                    }

                    "pressBack" -> {
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.pressBack())
                        }
                    }

                    "pressHome" -> {
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.pressHome())
                        }
                    }

                    "openNotifications" -> {
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.openNotifications())
                        }
                    }

                    "getCurrentPackage" -> {
                        val service = AgentAccessibilityService.instance
                        if (service == null) {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                        } else {
                            result.success(service.getCurrentPackage())
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
