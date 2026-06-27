import { NativeModules, Platform, TurboModuleRegistry } from 'react-native';
import type { Spec } from './NativeFitnessGeolocation';

const LINKING_ERROR =
  `The package 'react-native-fitness-geolocation' doesn't seem to be linked. ` +
  'Run pod install (iOS) and rebuild the app.';

/**
 * Resolve the native module with New Architecture preference.
 * - TurboModule when available
 * - Classic bridge NativeModules fallback
 */
/**
 * NOTE: Return type is intentionally `any` to preserve backward compatibility with
 * the existing JS surface while we migrate modules incrementally to typed calls.
 * The TurboModule spec remains the source of truth for codegen.
 */
export function getFitnessGeolocationNative(): any {
  const turbo = TurboModuleRegistry.get<Spec>('FitnessGeolocation');
  if (turbo) return turbo as any;

  const legacy = (NativeModules as any).FitnessGeolocation;
  if (legacy) return legacy as any;

  // Provide a proxy for consistent error messaging (mirrors prior behavior)
  return new Proxy(
    {},
    {
      get() {
        throw new Error(LINKING_ERROR + (Platform.OS === 'ios' ? '' : ''));
      },
    },
  ) as any;
}

