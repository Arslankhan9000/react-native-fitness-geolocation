/**
 * Shared kernel — permissions, types, platform helpers.
 * Import: `react-native-fitness-geolocation/core`
 */
export { PermissionManager } from '../PermissionManager';
export { PlatformSupport, requiresNotificationPermission, requiresBackgroundLocationPermission } from '../platform/PlatformSupport';
export { LogLevel, logLevelFromString, shouldPersistLog } from '../config/LogLevel';
export { applyLoggerConfig, resolveLoggerConfig } from '../config/ConfigManager';
export { normalizeConfig } from '../config/normalizeConfig';
export { PositionError } from '../types';
export type * from '../types';
