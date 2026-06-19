package com.fitnessgeolocation

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener

class FitnessGeolocationModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext),
  LocationEngine.Listener,
  PermissionListener,
  LifecycleEventListener {

  private val engine = LocationEngine.getInstance(reactContext)
  private var authPromise: Promise? = null
  private var pendingAuthLevel: String = "whenInUse"
  private var awaitingBackground = false

  companion object {
    private const val REQUEST_FINE = 1001
    private const val REQUEST_BACKGROUND = 1002
  }

  init {
    reactContext.addLifecycleEventListener(this)
    engine.addListener(this)
  }

  override fun getName(): String = "FitnessGeolocation"

  @ReactMethod
  fun addListener(eventName: String) {
    // Required by NativeEventEmitter. Native engine listeners are registered for module lifetime.
  }

  @ReactMethod
  fun removeListeners(count: Int) {
    // Required by NativeEventEmitter.
  }

  private fun sendEvent(event: String, params: WritableMap?) {
    reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  private fun hasFineLocation(): Boolean =
    ContextCompat.checkSelfPermission(reactContext, Manifest.permission.ACCESS_FINE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED

  private fun hasBackgroundLocation(): Boolean {
    if (Build.VERSION.SDK_INT < 29) return hasFineLocation()
    return ContextCompat.checkSelfPermission(
      reactContext, Manifest.permission.ACCESS_BACKGROUND_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
  }

  @ReactMethod
  fun getCurrentPosition(options: ReadableMap, promise: Promise) {
    if (!hasFineLocation()) {
      promise.reject("PERMISSION_DENIED", "Location permission not granted")
      return
    }
    engine.getCurrentPosition(options) { result ->
      result.onSuccess { promise.resolve(it.toPositionMap()) }
        .onFailure { promise.reject("POSITION_UNAVAILABLE", it.message, it) }
    }
  }

  @ReactMethod
  fun watchPosition(options: ReadableMap): Int {
    val watchId = engine.watchPosition(options)
    startForegroundTrackingService()
    return watchId
  }

  @ReactMethod
  fun clearWatch(watchId: Int) {
    engine.clearWatch(watchId)
    if (engine.activeWatchCount() == 0) stopForegroundTrackingService()
  }

  @ReactMethod
  fun stopLocationObserving() {
    engine.stopObserving()
    stopForegroundTrackingService()
  }

  @ReactMethod
  fun getPendingForJs(limit: Int, promise: Promise) {
    promise.resolve(engine.getPendingForJs(limit))
  }

  @ReactMethod
  fun markDelivered(ids: ReadableArray, promise: Promise) {
    val list = (0 until ids.size()).map { ids.getString(it)!! }
    promise.resolve(engine.markDelivered(list))
  }

  @ReactMethod
  fun purgeDelivered(promise: Promise) {
    promise.resolve(engine.purgeDelivered())
  }

  @ReactMethod
  fun getQueueSize(promise: Promise) {
    promise.resolve(engine.pendingCount())
  }

  @ReactMethod
  fun getDiagnostics(promise: Promise) {
    promise.resolve(engine.getDiagnostics())
  }

  @ReactMethod
  fun setConfiguration(config: ReadableMap, promise: Promise) {
    val editor = reactContext
      .getSharedPreferences("fitness_geolocation", android.content.Context.MODE_PRIVATE)
      .edit()

    if (config.hasKey("notificationTitle")) {
      editor.putString("notification_title", config.getString("notificationTitle"))
    }
    if (config.hasKey("notificationText")) {
      editor.putString("notification_text", config.getString("notificationText"))
    }
    if (config.hasKey("trackingMode")) {
      config.getString("trackingMode")?.let { engine.setTrackingMode(it) }
    }
    editor.apply()
    promise.resolve(null)
  }

  @ReactMethod
  fun requestAuthorization(level: String, promise: Promise) {
    pendingAuthLevel = level
    authPromise = promise

    if (hasFineLocation() && (level != "always" || hasBackgroundLocation())) {
      promise.resolve("granted")
      authPromise = null
      return
    }

    val activity = reactContext.currentActivity as? PermissionAwareActivity
    if (activity == null) {
      promise.resolve(if (hasFineLocation()) "granted" else "denied")
      authPromise = null
      return
    }

    if (!hasFineLocation()) {
      activity.requestPermissions(
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
        REQUEST_FINE,
        this,
      )
      return
    }

    if (level == "always" && Build.VERSION.SDK_INT >= 29 && !hasBackgroundLocation()) {
      awaitingBackground = true
      activity.requestPermissions(
        arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
        REQUEST_BACKGROUND,
        this,
      )
      return
    }

    promise.resolve("granted")
    authPromise = null
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ): Boolean {
    val promise = authPromise ?: return false

    when (requestCode) {
      REQUEST_FINE -> {
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
          promise.resolve("denied")
          authPromise = null
          emitAuthChange("denied")
          return true
        }
        emitAuthChange("granted")
        if (pendingAuthLevel == "always" && Build.VERSION.SDK_INT >= 29 && !hasBackgroundLocation()) {
          awaitingBackground = true
          val activity = reactContext.currentActivity as? PermissionAwareActivity
          activity?.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            REQUEST_BACKGROUND,
            this,
          ) ?: run {
            promise.resolve("granted")
            authPromise = null
          }
          return true
        }
        promise.resolve("granted")
        authPromise = null
      }
      REQUEST_BACKGROUND -> {
        awaitingBackground = false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        promise.resolve(if (granted) "granted" else "foreground_only")
        authPromise = null
        emitAuthChange(if (granted) "granted" else "foreground_only")
      }
    }
    return true
  }

  private fun emitAuthChange(status: String) {
    val map = Arguments.createMap()
    map.putString("status", status)
    sendEvent("authorizationChange", map)
  }

  private fun startForegroundTrackingService() {
    if (!hasFineLocation()) return
    val intent = Intent(reactContext, FitnessLocationService::class.java)
      .setAction(FitnessLocationService.ACTION_START)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      ContextCompat.startForegroundService(reactContext, intent)
    } else {
      reactContext.startService(intent)
    }
  }

  private fun stopForegroundTrackingService() {
    reactContext.stopService(Intent(reactContext, FitnessLocationService::class.java))
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
    engine.setTrackingMode(mode)
    promise.resolve(null)
  }

  @ReactMethod
  fun setActivityPaused(paused: Boolean, promise: Promise) {
    engine.setPaused(paused)
    promise.resolve(null)
  }

  @ReactMethod
  fun getEngineState(promise: Promise) {
    promise.resolve(engine.getEngineState())
  }

  @ReactMethod
  fun getAuthorizationStatus(promise: Promise) {
    val fine = hasFineLocation()
    val background = hasBackgroundLocation()
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

  override fun onEnterForeground() {
    val map = Arguments.createMap()
    map.putInt("pending", engine.pendingCount())
    sendEvent("foregroundSync", map)
  }

  override fun onDiagnostic(event: WritableMap) {
    sendEvent("diagnostic", event)
  }

  override fun onHostResume() {
    engine.onHostResume()
  }

  override fun onHostPause() {}
  override fun onHostDestroy() {
    engine.removeListener(this)
  }
  override fun invalidate() {
    engine.removeListener(this)
    super.invalidate()
  }
}
