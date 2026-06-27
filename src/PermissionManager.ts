import { Linking, PermissionsAndroid, Platform } from 'react-native';
import type { FitnessPermissionResult } from './types';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();

const ANDROID_FINE = PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION;
const ANDROID_BACKGROUND = PermissionsAndroid.PERMISSIONS.ACCESS_BACKGROUND_LOCATION;
const ANDROID_MOTION = PermissionsAndroid.PERMISSIONS.ACTIVITY_RECOGNITION;
const ANDROID_NOTIFICATIONS = PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS;

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

/** Android 13+ (API 33) — required to show foreground-service tracking notifications */
async function requestAndroidNotifications(): Promise<boolean> {
  if (Platform.OS !== 'android' || Number(Platform.Version) < 33) return true;
  return requestAndroidPermission(
    ANDROID_NOTIFICATIONS,
    {
      title: 'Workout notifications',
      message: 'Allow notifications so you can see live workout tracking on the lock screen.',
    },
  );
}

/**
 * Cross-platform permission helpers for fitness / background GPS apps.
 * Supports Android 9 (API 28) through Android 15/16+ and iOS 16.1+.
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

  async requestNotifications(): Promise<boolean> {
    if (Platform.OS === 'ios') return true;
    return requestAndroidNotifications();
  },

  /**
   * Recommended flow for fitness apps:
   * 1. Foreground location → 2. Background / Always → 3. Notifications (Android 13+)
   * → 4. Motion (Android 10+)
   */
  async requestFitnessPermissions(options?: {
    includeMotion?: boolean;
    includeNotifications?: boolean;
  }): Promise<FitnessPermissionResult> {
    const fg = await this.requestForeground();
    if (!fg) {
      return {
        foregroundGranted: false,
        backgroundGranted: false,
        motionGranted: false,
        notificationsGranted: false,
        status: 'denied',
        message: 'Location permission is required to track activities.',
      };
    }

    const bg = await this.requestBackground();
    const notifications = options?.includeNotifications !== false
      ? await this.requestNotifications()
      : true;
    const motion = options?.includeMotion ? await this.requestMotion() : true;
    const statusRes = await Native.getAuthorizationStatus();

    let status: FitnessPermissionResult['status'] = 'ready';
    if (!statusRes.always) status = 'foreground_only';
    if (!bg && Platform.OS === 'android') status = 'foreground_only';

    return {
      foregroundGranted: true,
      backgroundGranted: statusRes.always || bg,
      motionGranted: motion,
      notificationsGranted: notifications,
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
