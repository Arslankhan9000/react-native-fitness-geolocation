import { PermissionsAndroid, Platform } from 'react-native';
import { getPedometerNative } from './nativeBridge';
import type { PedometerPermissionStatus, PedometerSupportResult } from './types';

const ANDROID_MOTION = PermissionsAndroid.PERMISSIONS.ACTIVITY_RECOGNITION;
const ANDROID_BODY_BG = 'android.permission.BODY_SENSORS_BACKGROUND' as const;

async function requestAndroidMotion(): Promise<boolean> {
  if (Platform.OS !== 'android' || Number(Platform.Version) < 29) return true;
  const already = await PermissionsAndroid.check(ANDROID_MOTION);
  if (already) return true;
  const result = await PermissionsAndroid.request(ANDROID_MOTION, {
    title: 'Activity recognition',
    message: 'Used to count your steps during workouts without GPS.',
    buttonPositive: 'Allow',
    buttonNegative: 'Deny',
  });
  return result === PermissionsAndroid.RESULTS.GRANTED;
}

/** Android 14+ — optional for background step sensor without a foreground notification */
async function requestAndroidBodySensorsBackground(): Promise<boolean> {
  if (Platform.OS !== 'android' || Number(Platform.Version) < 34) return true;
  try {
    const already = await PermissionsAndroid.check(ANDROID_BODY_BG);
    if (already) return true;
    const result = await PermissionsAndroid.request(ANDROID_BODY_BG, {
      title: 'Background sensors',
      message: 'Allows step counting while the app is in the background (no notification).',
      buttonPositive: 'Allow',
      buttonNegative: 'Not now',
    });
    return result === PermissionsAndroid.RESULTS.GRANTED;
  } catch {
    return false;
  }
}

export const PedometerPermission = {
  async getSupport(): Promise<PedometerSupportResult> {
    const native = getPedometerNative();
    if (!native?.pedometerIsSupported) {
      return {
        supported: false,
        granted: false,
        status: 'unknown',
        platform: Platform.OS === 'ios' ? 'ios' : 'android',
      };
    }
    try {
      return (await native.pedometerIsSupported()) as unknown as PedometerSupportResult;
    } catch {
      return {
        supported: false,
        granted: false,
        status: 'unknown',
        platform: Platform.OS === 'ios' ? 'ios' : 'android',
      };
    }
  },

  async request(): Promise<PedometerPermissionStatus> {
    if (Platform.OS === 'ios') {
      const support = await this.getSupport();
      return support.status;
    }
    const motion = await requestAndroidMotion();
    if (!motion) return 'denied';
    await requestAndroidBodySensorsBackground();
    const after = await this.getSupport();
    return after.granted ? 'granted' : 'denied';
  },
};
