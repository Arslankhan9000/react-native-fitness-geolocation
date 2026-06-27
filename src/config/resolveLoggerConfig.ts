import type { BackgroundGeolocationConfig, LoggerConfig } from '../types';
import { LogLevel } from './LogLevel';

const DEFAULT_LOGGER: Required<Pick<LoggerConfig, 'logLevel' | 'logMaxDays'>> & LoggerConfig = {
  debug: false,
  sound: true,
  vibration: true,
  feedbackThrottleMs: 1500,
  notificationDebounceMs: 1200,
  stopTimeout: 5,
  heartbeatInterval: 60,
  stopAfterElapsedMinutes: 0,
  logLevel: LogLevel.Off,
  logMaxDays: 3,
};

/**
 * Normalize logger/debug settings from any supported config shape:
 * - `logger: { debug, logLevel, ... }` (preferred, Transistorsoft-style)
 * - legacy root `debug: true`
 */
export function resolveLoggerConfig(config: Partial<BackgroundGeolocationConfig> = {}): LoggerConfig {
  const nested = config.logger ?? {};
  const debug = nested.debug ?? config.debug ?? DEFAULT_LOGGER.debug;

  return {
    ...DEFAULT_LOGGER,
    ...nested,
    debug,
    notificationTitle: nested.notificationTitle ?? config.notificationTitle,
  };
}
