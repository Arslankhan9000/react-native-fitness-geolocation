package com.fitnessgeolocation

import android.content.Context
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.ConcurrentLinkedQueue

// ─── Motion State Machine ───────────────────────────────────────────────────

enum class MotionState { moving, stationary }

class MotionStateMachine {
  var state: MotionState = MotionState.stationary
  var stopTimeoutMinutes: Long = 5
  var currentActivity: String = "unknown"
  var currentConfidence: Double = 0.0
  var stateSince: Long = System.currentTimeMillis()
  var stopTimerRemaining: Long = 0

  private var stopTimer: Runnable? = null
  private val handler = Handler(Looper.getMainLooper())
  var delegate: MotionStateMachineDelegate? = null

  fun feedActivity(activity: String, confidence: Double) {
    currentActivity = activity
    currentConfidence = confidence

    when (activity) {
      "walking", "running", "cycling", "driving" -> transitionTo(MotionState.moving)
      "stationary", "unknown" -> startStopTimeout()
    }
  }

  fun feedSpeed(speed: Float) {
    if (speed > 0.5f && state == MotionState.stationary) {
      transitionTo(MotionState.moving)
    }
  }

  private fun startStopTimeout() {
    if (state == MotionState.stationary) return
    if (stopTimer != null) return

    stopTimerRemaining = stopTimeoutMinutes * 60
    val runnable = Runnable {
      stopTimer = null
      stopTimerRemaining = 0
      transitionTo(MotionState.stationary)
      delegate?.onEvent("stop_timeout_start", "Stop timeout elapsed — now stationary")
      delegate?.onSound("stop_timeout_start")
    }
    stopTimer = runnable
    handler.postDelayed(runnable, stopTimeoutMinutes * 60 * 1000)

    delegate?.onEvent("stop_timeout_start", "Device still — stop timeout ${stopTimeoutMinutes}min started")
    delegate?.onSound("stop_timeout_start")
  }

  fun cancelStopTimeout() {
    stopTimer?.let { handler.removeCallbacks(it) }
    stopTimer = null
    stopTimerRemaining = 0
    delegate?.onEvent("stop_timeout_cancel", "Device moved — stop timeout cancelled")
    delegate?.onSound("stop_timeout_cancel")
  }

  private fun transitionTo(newState: MotionState) {
    if (state == newState) {
      if (newState == MotionState.moving) cancelStopTimeout()
      return
    }

    val oldState = state
    state = newState
    stateSince = System.currentTimeMillis()

    if (newState == MotionState.moving) {
      cancelStopTimeout()
    }

    delegate?.onStateChange(newState, oldState, currentActivity)
    delegate?.onSound(if (newState == MotionState.moving) "motionchange_true" else "motionchange_false")

    val msg = if (newState == MotionState.moving) "Started moving — $currentActivity" else "Stopped — now stationary"
    delegate?.onEvent("motionchange", msg)
  }

  fun reset() {
    stopTimer?.let { handler.removeCallbacks(it) }
    stopTimer = null
    stopTimerRemaining = 0
    state = MotionState.stationary
    stateSince = System.currentTimeMillis()
    currentActivity = "unknown"
  }

  fun toMap(): Map<String, Any?> = mapOf(
    "state" to state.name,
    "activity" to currentActivity,
    "confidence" to currentConfidence,
    "sinceTimestamp" to stateSince.toDouble(),
    "stopTimeoutRemaining" to stopTimerRemaining.toDouble(),
  )
}

interface MotionStateMachineDelegate {
  fun onStateChange(newState: MotionState, oldState: MotionState, activity: String)
  fun onEvent(event: String, message: String)
  fun onSound(sound: String)
}

// ─── Heartbeat Engine ───────────────────────────────────────────────────────

class HeartbeatEngine {
  var intervalSeconds: Long = 60
  var delegate: HeartbeatEngineDelegate? = null

  private val handler = Handler(Looper.getMainLooper())
  private var runnable: Runnable? = null

  fun start() {
    stop()
    val r = object : Runnable {
      override fun run() {
        delegate?.onHeartbeat(mapOf(
          "event" to "heartbeat",
          "message" to "Heartbeat",
          "timestamp" to System.currentTimeMillis().toDouble(),
        ))
        delegate?.onSound("heartbeat")
        handler.postDelayed(this, intervalSeconds * 1000)
      }
    }
    runnable = r
    handler.postDelayed(r, intervalSeconds * 1000)
  }

  fun stop() {
    runnable?.let { handler.removeCallbacks(it) }
    runnable = null
  }
}

interface HeartbeatEngineDelegate {
  fun onHeartbeat(event: Map<String, Any?>)
  fun onSound(sound: String)
}

// ─── Sound Manager ──────────────────────────────────────────────────────────

class DebugSoundManager(private val context: Context) {
  var soundEnabled = true

  fun play(sound: String) {
    if (!soundEnabled) return
    try {
      val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
      val ringtone = RingtoneManager.getRingtone(context, uri)
      ringtone.play()
      Log.d("FitnessGeoSound", "sound: $sound")
    } catch (e: Exception) {
      Log.w("FitnessGeoSound", "sound_failed: ${e.message}")
    }
  }
}

// ─── DebugMonitor (Orchestrator) ────────────────────────────────────────────

interface DebugMonitorDelegate {
  fun onEnabledChange(enabled: Boolean)
  fun onMotionState(state: Map<String, Any?>)
  fun onHeartbeatEvent(event: Map<String, Any?>)
  fun onLifecycleEvent(event: Map<String, Any?>)
}

class DebugMonitor(private val context: Context) {
  val stateMachine = MotionStateMachine()
  val heartbeat = HeartbeatEngine()
  val sounds = DebugSoundManager(context)

  var delegate: DebugMonitorDelegate? = null

  private var _enabled = false
  private val tag = "FitnessGeoDebug"

  // Activity → notification text mapping
  private var notificationTexts = mutableMapOf(
    "stationary" to "Stationary",
    "walking" to "Walking",
    "running" to "Running",
    "cycling" to "Cycling",
    "driving" to "Driving",
    "unknown" to "Stationary",
    "moving" to "Moving",
  )
  private var notificationTitle = "Tracking activity"

  var enabled: Boolean
    get() = _enabled
    set(value) {
      val changed = _enabled != value
      _enabled = value
      if (changed) {
        delegate?.onEnabledChange(value)
        emitLifecycle("enabledChange", if (value) "Debug monitoring enabled" else "Debug monitoring disabled")
      }
    }

  init {
    stateMachine.delegate = object : MotionStateMachineDelegate {
      override fun onStateChange(newState: MotionState, oldState: MotionState, activity: String) {
        val payload = stateMachine.toMap()
        delegate?.onMotionState(payload)
        emitLifecycle("motionStateChange", "State: ${newState.name} — $activity")
        updateNotificationText(activity)
      }

      override fun onEvent(event: String, message: String) {
        emitLifecycle(event, message)
      }

      override fun onSound(sound: String) {
        sounds.play(sound)
      }
    }

    heartbeat.delegate = object : HeartbeatEngineDelegate {
      override fun onHeartbeat(event: Map<String, Any?>) {
        delegate?.onHeartbeatEvent(event)
      }

      override fun onSound(sound: String) {
        sounds.play(sound)
      }
    }
  }

  fun configure(config: Map<String, Any?>) {
    config["stopTimeoutMinutes"]?.let { stateMachine.stopTimeoutMinutes = (it as Number).toLong() }
    config["heartbeatIntervalSeconds"]?.let { heartbeat.intervalSeconds = (it as Number).toLong() }
    config["sound"]?.let { sounds.soundEnabled = it as Boolean }

    config["notificationTextStationary"]?.let { notificationTexts["stationary"] = it.toString() }
    config["notificationTextWalking"]?.let { notificationTexts["walking"] = it.toString() }
    config["notificationTextRunning"]?.let { notificationTexts["running"] = it.toString() }
    config["notificationTextCycling"]?.let { notificationTexts["cycling"] = it.toString() }
    config["notificationTextDriving"]?.let { notificationTexts["driving"] = it.toString() }
    config["notificationTextMoving"]?.let { notificationTexts["moving"] = it.toString() }
    config["notificationTitle"]?.let { notificationTitle = it.toString() }

    enabled = config["enabled"] as? Boolean ?: enabled

    if (enabled) {
      heartbeat.start()
      emitLifecycle("configured", "Debug monitor configured")
    } else {
      heartbeat.stop()
    }

    Log.d(tag, "configured enabled=$enabled stopTimeout=${stateMachine.stopTimeoutMinutes}min heartbeat=${heartbeat.intervalSeconds}s")
  }

  fun feedActivity(activity: String, confidence: Double) {
    if (!enabled) return
    stateMachine.feedActivity(activity, confidence)
    updateNotificationText(activity)
  }

  fun feedSpeed(speed: Float) {
    if (!enabled) return
    stateMachine.feedSpeed(speed)
  }

  fun getMotionState(): Map<String, Any?> = stateMachine.toMap()

  fun reset() {
    stateMachine.reset()
    heartbeat.stop()
    enabled = false
  }

  private fun updateNotificationText(activity: String) {
    val text = when (activity) {
      "walking" -> notificationTexts["walking"] ?: "Walking"
      "running" -> notificationTexts["running"] ?: "Running"
      "cycling" -> notificationTexts["cycling"] ?: "Cycling"
      "driving" -> notificationTexts["driving"] ?: "Driving"
      "stationary" -> notificationTexts["stationary"] ?: "Stationary"
      else -> if (stateMachine.state == MotionState.moving)
        notificationTexts["moving"] ?: "Moving"
      else
        notificationTexts["stationary"] ?: "Stationary"
    }

    // Store for FitnessLocationService to read
    context.getSharedPreferences("fitness_geolocation", Context.MODE_PRIVATE)
      .edit()
      .putString("notification_text", text)
      .putString("notification_title", notificationTitle)
      .apply()
  }

  private fun emitLifecycle(event: String, message: String, data: Map<String, Any?> = emptyMap()) {
    val payload = mutableMapOf<String, Any?>()
    payload.putAll(data)
    payload["event"] = event
    payload["message"] = message
    payload["timestamp"] = System.currentTimeMillis().toDouble()
    delegate?.onLifecycleEvent(payload)

    Log.d(tag, "[$event] $message")
  }
}
