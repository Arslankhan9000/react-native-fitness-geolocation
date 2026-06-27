import { getFitnessGeolocationNative } from '../native/getNativeModule';

type NativePedometer = {
  pedometerIsSupported?: () => Promise<Record<string, unknown>>;
  pedometerStart?: (sessionId: string | null) => Promise<Record<string, unknown>>;
  pedometerStop?: () => Promise<Record<string, unknown>>;
  pedometerGetSnapshot?: () => Promise<Record<string, unknown>>;
  pedometerOnAppForeground?: () => void;
  pedometerGetDiagnostics?: () => Promise<Record<string, unknown>>;
};

let cached: NativePedometer | null = null;

/** Lazy native resolve — avoids throwing at import time if module loads later. */
export function getPedometerNative(): NativePedometer | null {
  if (cached) return cached;
  try {
    const n = getFitnessGeolocationNative();
    if (n && typeof n === 'object') {
      cached = n as NativePedometer;
      return cached;
    }
  } catch {
    /* not linked yet */
  }
  return null;
}

export async function callNative<T>(
  method: keyof NativePedometer,
  fallback: T,
  invoke: (native: NativePedometer) => Promise<T>,
): Promise<T> {
  const native = getPedometerNative();
  if (!native || typeof native[method] !== 'function') {
    return fallback;
  }
  try {
    return await invoke(native);
  } catch {
    return fallback;
  }
}
