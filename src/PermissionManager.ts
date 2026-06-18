import { Linking, NativeModules, Platform } from 'react-native';

const Native = NativeModules.MicimGeolocation;

export type PermissionLevel = 'whenInUse' | 'always';

export interface FitnessPermissionResult {
  foregroundGranted: boolean;
  backgroundGranted: boolean;
  motionGranted: boolean;
  status: 'ready' | 'foreground_only' | 'denied' | 'blocked';
  message?: string;
}

/**
 * Strava-class permission flow — foreground first, then background (Always on iOS).
 * Handles platform differences so app code stays one-liner.
 */
export const PermissionManager = {
  async getStatus(): Promise<{
    location: string;
    always: boolean;
  }> {
    const res = await Native.getAuthorizationStatus();
    return { location: res.status, always: res.always };
  },

  async requestForeground(): Promise<boolean> {
    const status = await Native.requestAuthorization('whenInUse');
    return status === 'granted';
  },

  async requestBackground(): Promise<boolean> {
    const status = await Native.requestAuthorization('always');
    return status === 'granted';
  },

  /**
   * Full fitness app flow:
   * 1. When In Use → 2. Always (iOS) / Background (Android)
   */
  async requestFitnessPermissions(): Promise<FitnessPermissionResult> {
    const fg = await this.requestForeground();
    if (!fg) {
      return {
        foregroundGranted: false,
        backgroundGranted: false,
        motionGranted: true,
        status: 'denied',
        message: 'Location permission is required to track activities.',
      };
    }

    const bg = await this.requestBackground();
    const statusRes = await Native.getAuthorizationStatus();

    return {
      foregroundGranted: true,
      backgroundGranted: statusRes.always || bg,
      motionGranted: true,
      status: statusRes.always ? 'ready' : 'foreground_only',
      message: statusRes.always
        ? undefined
        : 'For locked-screen tracking, enable "Always Allow" location in Settings.',
    };
  },

  openSettings(): Promise<void> {
    return Platform.OS === 'ios'
      ? Linking.openURL('app-settings:')
      : Linking.openSettings();
  },

  openBatterySettings(): Promise<void> {
    if (Platform.OS === 'android') {
      return Linking.sendIntent('android.settings.BATTERY_SAVER_SETTINGS').catch(() =>
        Linking.openSettings(),
      );
    }
    return Linking.openURL('app-settings:');
  },
};

export default PermissionManager;
