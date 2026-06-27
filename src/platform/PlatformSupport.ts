/**
 * Platform support matrix — single source for docs and runtime checks.
 * Android API levels: https://developer.android.com/tools/releases/platforms
 */
export const PlatformSupport = {
  /** Android 9 — library minimum */
  androidMinApi: 28,
  /** Android 15 — default compile/target in library gradle */
  androidTargetApi: 35,
  /** iOS 16.1 — ActivityKit / Live Activities floor */
  iosMinVersion: '16.1',
  /** iOS 17 — CLBackgroundActivitySession */
  iosBackgroundSessionMin: '17.0',
} as const;

export type AndroidApiLevel = typeof PlatformSupport.androidMinApi | 29 | 30 | 31 | 32 | 33 | 34 | 35 | 36;

/** True when POST_NOTIFICATIONS runtime permission is required (Android 13+) */
export function requiresNotificationPermission(androidApi: number): boolean {
  return androidApi >= 33;
}

/** True when separate background location permission is required (Android 10+) */
export function requiresBackgroundLocationPermission(androidApi: number): boolean {
  return androidApi >= 29;
}
