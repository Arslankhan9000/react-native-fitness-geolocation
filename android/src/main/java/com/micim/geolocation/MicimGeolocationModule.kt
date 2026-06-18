package com.micim.geolocation

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule

class MicimGeolocationModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext), LocationEngine.Listener {

  private val engine = LocationEngine(reactContext, this)

  override fun getName(): String = "MicimGeolocation"

  private fun sendEvent(event: String, params: WritableMap?) {
    reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  @ReactMethod
  fun getCurrentPosition(options: ReadableMap, promise: Promise) {
    engine.getCurrentPosition { result ->
      result.onSuccess { promise.resolve(it.toPositionMap()) }
        .onFailure { promise.reject("POSITION_UNAVAILABLE", it.message, it) }
    }
  }

  @ReactMethod
  fun watchPosition(options: ReadableMap): Int = engine.watchPosition(options)

  @ReactMethod
  fun clearWatch(watchId: Int) = engine.clearWatch(watchId)

  @ReactMethod
  fun stopObserving() = engine.stopObserving()

  @ReactMethod
  fun getPendingForJs(limit: Int, promise: Promise) {
    promise.resolve(engine.getPendingForJs(limit))
  }

  @ReactMethod
  fun getPendingLocations(limit: Int, promise: Promise) {
    promise.resolve(engine.getPendingForJs(limit))
  }

  @ReactMethod
  fun markDelivered(ids: ReadableArray, promise: Promise) {
    val list = (0 until ids.size()).map { ids.getString(it)!! }
    promise.resolve(engine.markDelivered(list))
  }

  @ReactMethod
  fun acknowledge(ids: ReadableArray, promise: Promise) {
    val list = (0 until ids.size()).map { ids.getString(it)!! }
    promise.resolve(engine.acknowledge(list))
  }

  @ReactMethod
  fun getQueueSize(promise: Promise) {
    promise.resolve(engine.pendingCount())
  }

  @ReactMethod
  fun purgeDelivered(promise: Promise) {
    promise.resolve(engine.purgeDelivered())
  }

  @ReactMethod
  fun requestAuthorization(level: String, promise: Promise) {
    val fine = ContextCompat.checkSelfPermission(
      reactContext, Manifest.permission.ACCESS_FINE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
    promise.resolve(if (fine) "granted" else "denied")
  }

  @ReactMethod
  fun configureAutoPause(enabled: Boolean, delaySeconds: Double, promise: Promise) {
    promise.resolve(null)
  }

  @ReactMethod
  fun startMotionTracking(includePedometer: Boolean, promise: Promise) {
    promise.resolve(null)
  }

  @ReactMethod
  fun stopMotionTracking(promise: Promise) {
    promise.resolve(null)
  }

  @ReactMethod
  fun setTrackingMode(mode: String, promise: Promise) {
    promise.resolve(null)
  }

  @ReactMethod
  fun setActivityPaused(paused: Boolean, promise: Promise) {
    promise.resolve(null)
  }

  @ReactMethod
  fun getEngineState(promise: Promise) {
    val map = Arguments.createMap()
    map.putBoolean("isWatching", false)
    map.putBoolean("isPaused", false)
    map.putString("mode", "fitness")
    map.putInt("pendingQueue", engine.pendingCount())
    map.putString("motionState", "unknown")
    map.putString("signalStrength", "medium")
    promise.resolve(map)
  }

  @ReactMethod
  fun getAuthorizationStatus(promise: Promise) {
    val fine = ContextCompat.checkSelfPermission(
      reactContext, Manifest.permission.ACCESS_FINE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
    val background = if (Build.VERSION.SDK_INT >= 29) {
      ContextCompat.checkSelfPermission(
        reactContext, Manifest.permission.ACCESS_BACKGROUND_LOCATION,
      ) == PackageManager.PERMISSION_GRANTED
    } else true
    val map = Arguments.createMap()
    map.putString("status", if (fine) "granted" else "denied")
    map.putBoolean("always", fine && background)
    promise.resolve(map)
  }

  override fun onLocationPersisted(location: StoredLocation, watchIds: List<Int>, deliverLive: Boolean) {
    if (!deliverLive) return
    for (watchId in watchIds) {
      val event = Arguments.createMap()
      event.putInt("watchId", watchId)
      event.putMap("position", location.toPositionMap())
      event.putString("nativeId", location.id)
      sendEvent("watchPosition", event)
    }
  }

  override fun onLocationError(message: String, watchIds: List<Int>) {
    for (watchId in watchIds) {
      val event = Arguments.createMap()
      event.putInt("watchId", watchId)
      val error = Arguments.createMap()
      error.putInt("code", 2)
      error.putString("message", message)
      event.putMap("error", error)
      sendEvent("watchPosition", event)
    }
  }
}
