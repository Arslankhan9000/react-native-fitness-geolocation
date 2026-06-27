import { Platform } from 'react-native';
import { debugMonitor } from '../DebugMonitor';
import { getFitnessGeolocationNative } from '../native/getNativeModule';
import type { BackgroundGeolocationConfig, LoggerConfig } from '../types';
import { LogLevel } from './LogLevel';
import { resolveLoggerConfig } from './resolveLoggerConfig';

const Native = getFitnessGeolocationNative();

export { resolveLoggerConfig };

/**
 * Apply logger + debug monitor settings to native engines.
 * Safe to call from `ready()`, `setConfig()`, or standalone.
 */
export async function applyLoggerConfig(config: Partial<BackgroundGeolocationConfig> = {}): Promise<LoggerConfig> {
  const logger = resolveLoggerConfig(config);

  try {
    await Native.configureLogger?.({
      logLevel: logger.logLevel ?? LogLevel.Off,
      logMaxDays: logger.logMaxDays ?? 3,
    });
  } catch {
    // Older native builds may not expose configureLogger yet — non-fatal.
  }

  if (logger.debug) {
    await debugMonitor.configure({
      debug: true,
      sound: logger.sound,
      vibration: logger.vibration ?? Platform.OS === 'android',
      feedbackThrottleMs: logger.feedbackThrottleMs,
      notificationDebounceMs: logger.notificationDebounceMs,
      stopTimeout: logger.stopTimeout,
      heartbeatInterval: logger.heartbeatInterval,
      stopAfterElapsedMinutes: logger.stopAfterElapsedMinutes,
      notificationTitle: logger.notificationTitle,
      notificationTextStationary: logger.notificationTextStationary,
      notificationTextWalking: logger.notificationTextWalking,
      notificationTextRunning: logger.notificationTextRunning,
      notificationTextCycling: logger.notificationTextCycling,
      notificationTextDriving: logger.notificationTextDriving,
      notificationTextMoving: logger.notificationTextMoving,
    });
  } else {
    await debugMonitor.disable();
  }

  return logger;
}
