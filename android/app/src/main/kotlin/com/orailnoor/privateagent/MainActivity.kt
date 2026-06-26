package com.orailnoor.privateagent

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.privateagent/accessibility"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "isServiceRunning" -> {
                        result.success(AgentAccessibilityService.isRunning())
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
