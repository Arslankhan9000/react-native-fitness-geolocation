import { Platform } from 'react-native';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();

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
 * Fire-and-forget — elapsed time ticks on the lock screen via native `.timer` style;
 * you do not need to push every second.
 *
 * @param duration  Legacy bridge param (ignored by native widget timer)
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
   * End the Live Activity and dismiss it from the lock screen immediately.
   */
  async end(distance: number, duration: number, calories: number): Promise<void> {
    if (Platform.OS !== 'ios') return;
    return Native.endLiveActivity(distance, duration, calories);
  },

  /**
   * Dismiss all Live Activities (stale widgets after crash or without a clean stop).
   */
  async dismissAll(): Promise<void> {
    if (Platform.OS !== 'ios') return;
    return Native.dismissAllLiveActivities?.();
  },
};
