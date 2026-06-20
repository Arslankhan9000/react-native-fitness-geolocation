import { Linking, NativeModules, PermissionsAndroid, Platform } from 'react-native';
import type { FitnessPermissionResult } from './types';

const LINKING_ERROR =
  `The package 'react-native-fitness-geolocation' doesn't seem to be linked. ` +
  'Run pod install (iOS) and rebuild the app.';

const Native = NativeModules.FitnessGeolocation
  ? NativeModules.FitnessGeolocation
  : new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

const ANDROID_FINE = PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION;
const ANDROID_BACKGROUND = PermissionsAndroid.PERMISSIONS.ACCESS_BACKGROUND_LOCATION;
const ANDROID_MOTION = PermissionsAndroid.PERMISSIONS.ACTIVITY_RECOGNITION;

async function requestAndroidPermission(
  permission: (typeof PermissionsAndroid.PERMISSIONS)[keyof typeof PermissionsAndroid.PERMISSIONS],
  rationale?: { title: string; message: string },
): Promise<boolean> {
  const already = await PermissionsAndroid.check(permission);
  if (already) return true;

  const result = await PermissionsAndroid.request(permission, {
    title: rationale?.title ?? 'Location permission',
    message: rationale?.message ?? 'This app needs location access to track your activity.',
    buttonPositive: 'Allow',
    buttonNegative: 'Deny',
  });

  return result === PermissionsAndroid.RESULTS.GRANTED;
}

async function requestAndroidBackground(): Promise<boolean> {
  if (Number(Platform.Version) < 29) return true;
  const fine = await PermissionsAndroid.check(ANDROID_FINE);
  if (!fine) return false;
  return requestAndroidPermission(
    ANDROID_BACKGROUND,
    {
      title: 'Background location',
      message: 'Allow background location so tracking continues when the screen is off.',
    },
  );
}

async function requestAndroidMotion(): Promise<boolean> {
  if (Platform.OS !== 'android' || Number(Platform.Version) < 29) return true;
  return requestAndroidPermission(
    ANDROID_MOTION,
    {
      title: 'Activity recognition',
      message: 'Used for auto-pause when you stop moving during a workout.',
    },
  );
}

/**
 * Cross-platform permission helpers for fitness / background GPS apps.
 */
export const PermissionManager = {
  async getStatus(): Promise<{ location: string; always: boolean }> {
    const res = await Native.getAuthorizationStatus();
    return { location: res.status, always: res.always };
  },

  async requestForeground(): Promise<boolean> {
    if (Platform.OS === 'ios') {
      const status = await Native.requestAuthorization('whenInUse');
      return status === 'granted';
    }
    return requestAndroidPermission(ANDROID_FINE);
  },

  async requestBackground(): Promise<boolean> {
    if (Platform.OS === 'ios') {
      const status = await Native.requestAuthorization('always');
      return status === 'granted';
    }
    const fg = await this.requestForeground();
    if (!fg) return false;
    return requestAndroidBackground();
  },

  async requestMotion(): Promise<boolean> {
    if (Platform.OS === 'ios') return true;
    return requestAndroidMotion();
  },

  /**
   * Recommended flow for fitness apps:
   * 1. Foreground location → 2. Background / Always → 3. Motion (Android)
   */
  async requestFitnessPermissions(options?: {
    includeMotion?: boolean;
  }): Promise<FitnessPermissionResult> {
    const fg = await this.requestForeground();
    if (!fg) {
      return {
        foregroundGranted: false,
        backgroundGranted: false,
        motionGranted: false,
        status: 'denied',
        message: 'Location permission is required to track activities.',
      };
    }

    const bg = await this.requestBackground();
    const motion = options?.includeMotion ? await this.requestMotion() : true;
    const statusRes = await Native.getAuthorizationStatus();

    let status: FitnessPermissionResult['status'] = 'ready';
    if (!statusRes.always) status = 'foreground_only';
    if (!bg && Platform.OS === 'android') status = 'foreground_only';

    return {
      foregroundGranted: true,
      backgroundGranted: statusRes.always || bg,
      motionGranted: motion,
      status,
      message: status === 'ready'
        ? undefined
        : Platform.OS === 'ios'
          ? 'For locked-screen tracking, enable "Always Allow" in Settings → Location.'
          : 'For background tracking, grant "Allow all the time" in Settings → Location.',
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
