import { AppRegistry } from 'react-native';
import type { HeadlessEvent, HeadlessTaskCallback } from './types';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();

const TAG = 'FitnessGeolocationHeadlessTask';

/**
 * Android Headless Task support.
 *
 * When the app process is killed by Android but the foreground service
 * continues tracking, native events are forwarded to this headless JS
 * task. The registered callback runs in a fresh JS context.
 *
 * This is how Strava/Nike continue uploading even when the user
 * swipes the app away on Android.
 *
 * Usage — call ONCE in your index.js (root file):
 * ```js
 * import { registerHeadlessTask } from 'react-native-fitness-geolocation';
 *
 * registerHeadlessTask(async (event) => {
 *   if (event.name === 'location') {
 *     await uploadToServer(event.params.location);
 *   }
 * });
 * ```
 */

let registered = false;

/**
 * Register a headless task callback.
 * Must be called from the root index.js file, outside any component.
 * The callback receives native events even when the app is killed.
 */
export function registerHeadlessTask(callback: HeadlessTaskCallback): void {
  if (registered) {
    if (__DEV__) {
      console.warn(`[${TAG}] Already registered — call once in index.js`);
    }
    return;
  }
  registered = true;

  AppRegistry.registerHeadlessTask(TAG, () => async (event: Record<string, unknown>) => {
    const headlessEvent: HeadlessEvent = {
      name: String(event.name ?? 'unknown'),
      params: (event.params as Record<string, unknown>) ?? {},
    };

    try {
      await callback(headlessEvent);
    } catch (error) {
      console.error(`[${TAG}] Error:`, error);
    }
  });

  if (__DEV__) {
    console.log(`[${TAG}] Registered headless task`);
    Native.devLog?.('info', TAG, 'registered', {});
  }
}

/**
 * Whether a headless task callback has been registered.
 */
export function isHeadlessTaskRegistered(): boolean {
  return registered;
}

export default { registerHeadlessTask, isHeadlessTaskRegistered };
