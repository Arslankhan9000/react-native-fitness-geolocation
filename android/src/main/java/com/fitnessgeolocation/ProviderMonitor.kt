package com.fitnessgeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.PowerManager
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap

/**
 * Provider / connectivity monitor using NetworkCallback (API 24+) instead of deprecated
 * CONNECTIVITY_ACTION broadcasts. Safe for API 28–35+.
 */
class ProviderMonitor(private val context: Context) {
  var onEvent: ((WritableMap) -> Unit)? = null

  private var powerReceiver: BroadcastReceiver? = null
  private var networkCallback: ConnectivityManager.NetworkCallback? = null
  private var lastPowerSave: Boolean? = null
  private var lastConnected: Boolean? = null

  fun start() {
    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    lastPowerSave = pm.isPowerSaveMode
    lastConnected = isConnected()

    powerReceiver = object : BroadcastReceiver() {
      override fun onReceive(ctx: Context, intent: Intent) {
        val save = pm.isPowerSaveMode
        if (save != lastPowerSave) {
          lastPowerSave = save
          emit(mapOf("event" to "powerSaveChange", "enabled" to save))
        }
      }
    }
    PlatformCompat.registerNotExportedReceiver(
      context,
      powerReceiver!!,
      IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
    )

    val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val callback = object : ConnectivityManager.NetworkCallback() {
      override fun onAvailable(network: Network) = updateConnectivity(true)
      override fun onLost(network: Network) = updateConnectivity(isConnected())
      override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
        val hasInternet = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
          caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        updateConnectivity(hasInternet)
      }
    }
    networkCallback = callback
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      cm.registerDefaultNetworkCallback(callback)
    } else {
      cm.registerNetworkCallback(
        NetworkRequest.Builder()
          .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
          .build(),
        callback,
      )
    }
  }

  fun stop() {
    powerReceiver?.let {
      try { context.unregisterReceiver(it) } catch (_: Exception) {}
    }
    networkCallback?.let { callback ->
      try {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.unregisterNetworkCallback(callback)
      } catch (_: Exception) {}
    }
    powerReceiver = null
    networkCallback = null
  }

  fun emitProviderState(state: WritableMap) {
    val map = Arguments.createMap()
    map.putString("event", "providerChange")
    map.putBoolean("enabled", state.getBoolean("enabled"))
    map.putString("status", state.getString("status"))
    onEvent?.invoke(map)
  }

  private fun updateConnectivity(connected: Boolean) {
    if (connected != lastConnected) {
      lastConnected = connected
      emit(mapOf("event" to "connectivityChange", "connected" to connected))
    }
  }

  private fun emit(data: Map<String, Any>) {
    onEvent?.invoke(Arguments.makeNativeMap(data))
  }

  private fun isConnected(): Boolean {
    val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val net = cm.activeNetwork ?: return false
    val caps = cm.getNetworkCapabilities(net) ?: return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
  }
}
