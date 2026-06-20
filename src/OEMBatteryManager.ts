import { Linking, NativeModules, Platform } from 'react-native';
import type { OEMBatteryInfo } from './types';

const Native = NativeModules.FitnessGeolocation;

/**
 * OEM Battery Manager — handles per-manufacturer battery optimization settings.
 *
 * Problem: Android OEMs (Xiaomi, Huawei, Oppo, Vivo, OnePlus, Samsung) each
 * have their own battery management systems that aggressively kill foreground
 * services. The generic `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` intent doesn't
 * work on most Chinese OEMs — they require manufacturer-specific settings intents.
 *
 * This module provides:
 * 1. Request battery optimization exemption (stock Android)
 * 2. OEM-specific settings intents (per manufacturer)
 * 3. Detection of whether the app is already exempt
 */
export const OEMBatteryManager = {
  /**
   * Request battery optimization exemption (stock Android).
   * Shows system dialog to allow the app to ignore battery optimizations.
   * This is the first line of defense against Doze mode.
   */
  async requestExemption(): Promise<boolean> {
    if (Platform.OS !== 'android') return true;

    try {
      const result = await Native.requestBatteryOptimizationPermission?.();
      return result === true;
    } catch {
      // Fallback: open system battery settings
      await this.openBatterySettings();
      return false;
    }
  },

  /**
   * Open the manufacturer-specific battery settings screen.
   * On stock Android, opens the battery optimization settings.
   * On OEM devices, opens the manufacturer's battery management app.
   */
  async openOemBatterySettings(): Promise<boolean> {
    if (Platform.OS !== 'android') {
      // iOS: open system settings
      await Linking.openURL('app-settings:');
      return true;
    }

    try {
      await Native.openOemBatterySettings?.();
      return true;
    } catch {
      // Fallback to generic battery settings
      await this.openBatterySettings();
      return false;
    }
  },

  /**
   * Open generic battery optimization settings.
   */
  async openBatterySettings(): Promise<void> {
    if (Platform.OS === 'android') {
      try {
        await Linking.sendIntent('android.settings.BATTERY_SAVER_SETTINGS');
      } catch {
        await Linking.openSettings();
      }
    } else {
      await Linking.openURL('app-settings:');
    }
  },

  /**
   * Open the app's system settings page.
   * On Android, this is where the user can manually disable battery optimization.
   */
  async openAppSettings(): Promise<void> {
    if (Platform.OS === 'android') {
      try {
        await Linking.openSettings();
      } catch {
        // Fallback
      }
    } else {
      await Linking.openURL('app-settings:');
    }
  },

  /**
   * Check if the app is currently exempt from battery optimization.
   */
  async isExempt(): Promise<boolean> {
    if (Platform.OS !== 'android') return true;

    try {
      const result = await Native.isIgnoringBatteryOptimizations?.();
      return result === true;
    } catch {
      return false;
    }
  },

  /**
   * Get information about the device's battery optimization state.
   */
  async getInfo(): Promise<OEMBatteryInfo> {
    const manufacturer = Platform.OS === 'android'
      ? (NativeModules.PlatformConstants?.Manufacturer ?? 'unknown')
      : 'apple';

    const isExempt = await this.isExempt();
    const oemName = this.getOemSettingsAppName(manufacturer);

    return {
      manufacturer: manufacturer.toLowerCase(),
      model: Platform.OS === 'android'
        ? (NativeModules.PlatformConstants?.Model ?? 'unknown')
        : Platform.Version.toString(),
      isBatteryOptimizationExempt: isExempt,
      canOpenOemSettings: oemName != null,
      oemSettingsAppName: oemName,
    };
  },

  /**
   * Get the OEM-specific battery settings app name for the given manufacturer.
   */
  getOemSettingsAppName(manufacturer: string): string | null {
    const mfr = manufacturer.toLowerCase();
    if (mfr.includes('xiaomi')) return 'MIUI Security Center';
    if (mfr.includes('huawei') || mfr.includes('honor')) return 'Huawei System Manager';
    if (mfr.includes('oppo')) return 'Oppo Battery Optimizer';
    if (mfr.includes('vivo')) return 'Vivo iQOO Security';
    if (mfr.includes('oneplus')) return 'OnePlus Security';
    if (mfr.includes('samsung')) return 'Samsung Device Care';
    if (mfr.includes('realme')) return 'Realme Phone Manager';
    return null;
  },

  /**
   * Show a user-friendly message explaining why battery optimization exemption is needed.
   * This should be called before requestExemption() to set context.
   */
  getRationale(manufacturer?: string): string {
    const mfr = (manufacturer ?? Platform.OS === 'android' ? 'your device' : '')
      .toLowerCase();

    if (Platform.OS === 'ios') {
      return 'To track your location in the background, please ensure Location Services is set to "Always" in Settings.';
    }

    if (mfr.includes('xiaomi')) {
      return 'Xiaomi MIUI restricts background apps. Please add this app to the "Autostart" whitelist and disable "Battery Saver" restrictions in the Security Center app.';
    }
    if (mfr.includes('huawei') || mfr.includes('honor')) {
      return 'Huawei/Honor devices restrict background apps. Please add this app to "Protected Apps" in Phone Manager and disable battery optimization.';
    }
    if (mfr.includes('oppo')) {
      return 'Oppo ColorOS restricts background apps. Please add this app to "Auto-Start" and disable "Battery Optimization" in Settings.';
    }
    if (mfr.includes('vivo')) {
      return 'Vivo/iQOO devices restrict background apps. Please add this app to "Autostart" and set "Background Activity" to "Always" in Settings.';
    }
    if (mfr.includes('oneplus')) {
      return 'OnePlus OxygenOS restricts background apps. Please disable "Optimize Battery" and "App Auto-Launch" restrictions for this app.';
    }
    if (mfr.includes('samsung')) {
      return 'Samsung One UI restricts background apps. Please set this app to "Unrestricted" under Battery and disable "Put app to sleep" in Device Care.';
    }
    if (mfr.includes('realme')) {
      return 'Realme UI restricts background apps. Please add this app to "Auto-Start" and disable "Background Freeze" in Phone Manager.';
    }

    return 'Please disable battery optimization for this app in System Settings to ensure reliable background tracking.';
  },
};

export default OEMBatteryManager;
