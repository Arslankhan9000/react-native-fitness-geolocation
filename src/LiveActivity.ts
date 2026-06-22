import { NativeModules, Platform } from 'react-native';

const LINKING_ERROR =
  `The package 'react-native-fitness-geolocation' doesn't seem to be linked. ` +
  'Run pod install (iOS) and rebuild the app.';

const Native = NativeModules.FitnessGeolocation
  ? NativeModules.FitnessGeolocation
  : new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

/**
 * Live Activity bridge — controls the Lock Screen / Dynamic Island workout widget.
 *
 * All methods are no-ops on Android and on iOS < 16.1 (handled natively).
 * The user must enable Live Activities from Appearance settings; they are OFF
 * by default and can be toggled without restarting a session.
 *
 * Update frequency: call `update()` on every GPS fix (native side throttles
 * ActivityKit pushes to avoid rate-limiting).
 */
export const LiveActivity = {
  /**
   * Persist user preference for Live Activities (survives app restarts).
   */
  setEnabled(enabled: boolean): void {
    if (Platform.OS !== 'ios') return;
    Native.setLiveActivityEnabled(enabled);
  },

  /**
   * Read current user preference.
   */
  async isEnabled(): Promise<boolean> {
    if (Platform.OS !== 'ios') return false;
    return Native.getLiveActivityEnabled();
  },

  /**
   * Start the Live Activity for a workout session.
   * Silently no-ops if user has not enabled Live Activities.
   */
  async start(name: string, activityType: string): Promise<void> {
    if (Platform.OS !== 'ios') return;
    return Native.startLiveActivity(name, activityType);
  },

  /**
   * Push updated workout metrics to the Live Activity.
   * Fire-and-forget — no await needed on the hot GPS path.
   *
   * @param distance  Meters travelled so far
   * @param duration  Seconds elapsed
   * @param pace      Formatted string e.g. "5:23"
   * @param speed     km/h
   * @param calories  kcal estimate
   * @param gpsStatus "strong" | "medium" | "weak" | "lost"
   * @param isPaused  Auto-pause state
   */
  update(
    distance: number,
    duration: number,
    pace: string,
    speed: number,
    calories: number,
    gpsStatus: string,
    isPaused: boolean,
  ): void {
    if (Platform.OS !== 'ios') return;
    Native.updateLiveActivity(distance, duration, pace, speed, calories, gpsStatus, isPaused);
  },

  /**
   * End the Live Activity and show a final summary for up to 4 hours.
   */
  async end(distance: number, duration: number, calories: number): Promise<void> {
    if (Platform.OS !== 'ios') return;
    return Native.endLiveActivity(distance, duration, calories);
  },
};
