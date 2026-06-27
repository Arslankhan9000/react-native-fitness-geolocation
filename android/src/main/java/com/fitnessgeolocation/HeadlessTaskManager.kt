package com.fitnessgeolocation

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.facebook.react.HeadlessJsTaskService
import com.facebook.react.bridge.Arguments
import com.facebook.react.jstasks.HeadlessJsTaskConfig
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Manages headless JS task execution when the app process is killed.
 *
 * When Android kills the app but the foreground service continues tracking
 * (via START_STICKY), this manager queues native events and dispatches them
 * to the registered JS headless task callback.
 *
 * Each queued event starts a new HeadlessJsTaskService invocation, which
 * React Native handles in a fresh JS context.
 */
object HeadlessTaskManager {
  internal const val TAG = "FitnessGeoHeadless"
  internal const val TASK_NAME = "FitnessGeolocationHeadlessTask"
  private val eventQueue = ConcurrentLinkedQueue<HeadlessTaskEvent>()
  private var isProcessing = false

  data class HeadlessTaskEvent(
    val name: String,
    val params: Map<String, Any?>,
  )

  /**
   * Queue a native event for headless JS execution.
   * If the app is in the foreground, the event is handled normally.
   * If the app is in the background or killed, this triggers a headless task.
   */
  fun queueEvent(context: Context, name: String, params: Map<String, Any?>) {
    eventQueue.add(HeadlessTaskEvent(name, params))
    Log.d(TAG, "event_queued: $name (queue_size: ${eventQueue.size})")
    processNext(context)
  }

  private fun processNext(context: Context) {
    if (isProcessing || eventQueue.isEmpty()) return
    isProcessing = true

    val event = eventQueue.poll() ?: run {
      isProcessing = false
      return
    }

    try {
      val intent = Intent(context, FitnessHeadlessTaskService::class.java).apply {
        putExtra("event_name", event.name)
        putExtra("event_params", HashMap(event.params))
      }
      context.startService(intent)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to start headless task: ${e.message}")
      isProcessing = false
    }
  }

  /** Called by FitnessHeadlessTaskService when JS finishes processing */
  fun onTaskFinished(context: Context) {
    isProcessing = false
    processNext(context)
  }
}

/**
 * Headless JS task service — runs a registered JS callback in a fresh
 * React Native context when the app is in the background.
 *
 * Each invocation delivers one native event (location, geofence, etc.)
 * to the JS callback registered via `AppRegistry.registerHeadlessTask`.
 */
class FitnessHeadlessTaskService : HeadlessJsTaskService() {
  private companion object {
    private const val TAG = HeadlessTaskManager.TAG
  }
  override fun getTaskConfig(intent: Intent?): HeadlessJsTaskConfig? {
    val eventName = intent?.getStringExtra("event_name") ?: return null
    @Suppress("DEPRECATION")
    val eventParams: HashMap<*, *>? = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
      intent.getSerializableExtra("event_params", HashMap::class.java)
    } else {
      intent.getSerializableExtra("event_params") as? HashMap<*, *>
    }
    if (eventParams == null) return null

    val params = Arguments.createMap().apply {
      putString("name", eventName)
      val paramsMap = Arguments.createMap()
      eventParams.forEach { (key, value) ->
        when (value) {
          is String -> paramsMap.putString(key as String, value)
          is Number -> paramsMap.putDouble(key as String, value.toDouble())
          is Boolean -> paramsMap.putBoolean(key as String, value)
          is Map<*, *> -> paramsMap.putMap(key as String, Arguments.makeNativeMap(value as Map<String, Any>))
        }
      }
      putMap("params", paramsMap)
    }

    Log.d(TAG, "headless_task: $eventName")

    return HeadlessJsTaskConfig(
      HeadlessTaskManager.TASK_NAME,
      params,
      0, // No timeout — task runs until promise resolves
      true // Allow task in foreground
    )
  }

  override fun onHeadlessJsTaskFinish(taskId: Int) {
    super.onHeadlessJsTaskFinish(taskId)
    HeadlessTaskManager.onTaskFinished(this)
  }

  override fun onDestroy() {
    super.onDestroy()
    Log.d(TAG, "service_destroyed")
  }
}
