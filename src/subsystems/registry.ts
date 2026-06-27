/**
 * Subsystem registry — documents modular import paths.
 */
export const SUBSYSTEMS = {
  core: 'react-native-fitness-geolocation/core',
  geolocation: 'react-native-fitness-geolocation/geolocation',
  pedometer: 'react-native-fitness-geolocation/pedometer',
  geofence: 'react-native-fitness-geolocation/geofence',
  activity: 'react-native-fitness-geolocation/activity',
  sync: 'react-native-fitness-geolocation/sync',
  diagnostics: 'react-native-fitness-geolocation/diagnostics',
} as const;

export type SubsystemId = keyof typeof SUBSYSTEMS;

/** Native binary note: JS subpath imports tree-shake; native code links as one pod until optional feature flags ship. */
export const NATIVE_LINKING_NOTE =
  'Subpath imports reduce JS bundle size. Native iOS/Android currently ship as a single module; optional native feature flags are planned.';
