package com.privateagent.private_agent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.hardware.HardwareBuffer
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.annotation.RequiresApi
import java.io.ByteArrayOutputStream

class AgentAccessibilityService : AccessibilityService() {

    companion object {
        var instance: AgentAccessibilityService? = null
            private set

        fun isRunning(): Boolean = instance != null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We don't need to react to events — we query on demand
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    // ─── Screen Reading ──────────────────────────────────────────

    /** Dump the current screen as a flat list of UI elements */
    fun dumpScreen(): List<Map<String, Any?>> {
        val root = rootInActiveWindow ?: return emptyList()
        val nodes = mutableListOf<Map<String, Any?>>()
        traverseNode(root, nodes, 0)
        root.recycle()
        return nodes
    }

    private fun traverseNode(
        node: AccessibilityNodeInfo,
        nodes: MutableList<Map<String, Any?>>,
        depth: Int
    ) {
        val rect = Rect()
        node.getBoundsInScreen(rect)

        val text = node.text?.toString() ?: ""
        val contentDesc = node.contentDescription?.toString() ?: ""
        val className = node.className?.toString() ?: ""
        val viewId = node.viewIdResourceName ?: ""

        // Only include nodes that have text/description or are interactive
        if (text.isNotEmpty() || contentDesc.isNotEmpty() ||
            node.isClickable || node.isEditable || node.isScrollable
        ) {
            nodes.add(
                mapOf(
                    "index" to nodes.size,
                    "text" to text,
                    "contentDescription" to contentDesc,
                    "className" to className.substringAfterLast('.'),
                    "viewId" to viewId,
                    "isClickable" to node.isClickable,
                    "isEditable" to node.isEditable,
                    "isScrollable" to node.isScrollable,
                    "isCheckable" to node.isCheckable,
                    "isChecked" to node.isChecked,
                    "isFocused" to node.isFocused,
                    "bounds" to mapOf(
                        "left" to rect.left,
                        "top" to rect.top,
                        "right" to rect.right,
                        "bottom" to rect.bottom
                    ),
                    "depth" to depth
                )
            )
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNode(child, nodes, depth + 1)
            child.recycle()
        }
    }

    /** Capture screenshot as Base64 string */
    @RequiresApi(Build.VERSION_CODES.R)
    fun takeScreenshot(callback: (String?) -> Unit) {
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshotResult: ScreenshotResult) {
                    val hardwareBuffer = screenshotResult.hardwareBuffer
                    val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, screenshotResult.colorSpace)
                        ?.copy(Bitmap.Config.ARGB_8888, false)
                    
                    hardwareBuffer.close()

                    if (bitmap != null) {
                        // Compress to lower quality JPEG to save bytes for the API
                        val byteArrayOutputStream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 60, byteArrayOutputStream)
                        val byteArray = byteArrayOutputStream.toByteArray()
                        val base64String = Base64.encodeToString(byteArray, Base64.NO_WRAP)
                        callback(base64String)
                    } else {
                        callback(null)
                    }
                }

                override fun onFailure(errorCode: Int) {
                    callback(null)
                }
            }
        )
    }

    // ─── Actions ─────────────────────────────────────────────────

    /** Find and click a node by its text content */
    fun clickByText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val result = findAndClickNode(root, targetText)
        root.recycle()
        return result
    }

    private fun findAndClickNode(node: AccessibilityNodeInfo, targetText: String): Boolean {
        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""

        if (text.equals(targetText, ignoreCase = true) ||
            desc.equals(targetText, ignoreCase = true) ||
            text.contains(targetText, ignoreCase = true) ||
            desc.contains(targetText, ignoreCase = true)
        ) {
            // Click this node or its clickable parent
            var clickTarget: AccessibilityNodeInfo? = node
            while (clickTarget != null && !clickTarget.isClickable) {
                clickTarget = clickTarget.parent
            }
            if (clickTarget != null) {
                val success = clickTarget.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                return success
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (findAndClickNode(child, targetText)) {
                child.recycle()
                return true
            }
            child.recycle()
        }
        return false
    }

    /** Click at specific coordinates using gesture */
    fun clickAtCoordinates(x: Float, y: Float): Boolean {
        val path = Path()
        path.moveTo(x, y)
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /** Find an editable field (optionally by hint/nearby text) and type into it */
    fun typeText(text: String, fieldHint: String? = null): Boolean {
        val root = rootInActiveWindow ?: return false
        val editNode = findEditableNode(root, fieldHint)
        if (editNode != null) {
            editNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            val args = Bundle()
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            val success = editNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            root.recycle()
            return success
        }
        root.recycle()
        return false
    }

    private fun findEditableNode(
        node: AccessibilityNodeInfo,
        hint: String?
    ): AccessibilityNodeInfo? {
        if (node.isEditable) {
            if (hint == null) return node
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            val hintText = node.hintText?.toString() ?: ""
            if (text.contains(hint, ignoreCase = true) ||
                desc.contains(hint, ignoreCase = true) ||
                hintText.contains(hint, ignoreCase = true)
            ) {
                return node
            }
            // If no hint match but this is the first editable, return it
            if (hint.isNullOrEmpty()) return node
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findEditableNode(child, hint)
            if (found != null) return found
            child.recycle()
        }
        return null
    }

    /** Scroll forward on the first scrollable element, or a specific one by text */
    fun scroll(direction: String, targetText: String? = null): Boolean {
        val root = rootInActiveWindow ?: return false
        val scrollNode = findScrollableNode(root, targetText)
        if (scrollNode != null) {
            val action = when (direction.lowercase()) {
                "down", "forward" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                "up", "backward" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                else -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            }
            val success = scrollNode.performAction(action)
            root.recycle()
            return success
        }
        root.recycle()
        return false
    }

    private fun findScrollableNode(
        node: AccessibilityNodeInfo,
        targetText: String?
    ): AccessibilityNodeInfo? {
        if (node.isScrollable) {
            if (targetText == null) return node
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            if (text.contains(targetText, ignoreCase = true) ||
                desc.contains(targetText, ignoreCase = true)
            ) {
                return node
            }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findScrollableNode(child, targetText)
            if (found != null) return found
            child.recycle()
        }
        return null
    }

    /** Press the global back button */
    fun pressBack(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_BACK)
    }

    /** Press the global home button */
    fun pressHome(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /** Open recent apps */
    fun openRecents(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_RECENTS)
    }

    /** Open notifications */
    fun openNotifications(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
    }

    /** Swipe gesture */
    fun swipe(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long = 300): Boolean {
        val path = Path()
        path.moveTo(startX, startY)
        path.lineTo(endX, endY)
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /** Long press at coordinates */
    fun longPressAt(x: Float, y: Float): Boolean {
        val path = Path()
        path.moveTo(x, y)
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 1000))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /** Get the currently focused app's package name */
    fun getCurrentPackage(): String? {
        val root = rootInActiveWindow ?: return null
        val pkg = root.packageName?.toString()
        root.recycle()
        return pkg
    }
}
