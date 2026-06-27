package com.fitnessgeolocation

import com.facebook.react.TurboReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager

/**
 * Package entry for autolinking.
 *
 * - Classic bridge: provides `FitnessGeolocationModule`
 * - New Architecture: the JS side prefers TurboModule (codegen). Native side can
 *   evolve to a codegen-backed module without breaking autolinking.
 */
class FitnessGeolocationPackage : TurboReactPackage() {

  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
    return if (name == FitnessGeolocationModule.NAME) FitnessGeolocationModule(reactContext) else null
  }

  override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
    return ReactModuleInfoProvider {
      mapOf(
        FitnessGeolocationModule.NAME to ReactModuleInfo(
          FitnessGeolocationModule.NAME,
          FitnessGeolocationModule.NAME,
          false, // canOverrideExistingModule
          false, // needsEagerInit
          true, // hasConstants
          false, // isCxxModule
          true, // isTurboModule (exposed as Turbo-capable via this package)
        ),
      )
    }
  }

  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
    return emptyList()
  }
}
