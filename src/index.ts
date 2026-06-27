/**
 * Full package barrel — backward compatible default import.
 *
 * Prefer subpath imports for smaller JS bundles:
 *   `react-native-fitness-geolocation/pedometer`
 *   `react-native-fitness-geolocation/geolocation`
 *   etc.
 */
export * from './subsystems/core';
export * from './subsystems/geolocation';
export * from './subsystems/pedometer';
export * from './subsystems/geofence';
export * from './subsystems/activity';
export * from './subsystems/sync';
export * from './subsystems/diagnostics';
export { SUBSYSTEMS, NATIVE_LINKING_NOTE } from './subsystems/registry';
export type { SubsystemId } from './subsystems/registry';

// Default export = Geolocation (unchanged)
export { default } from './Geolocation';
