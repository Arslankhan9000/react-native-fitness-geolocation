import { AppState, NativeEventEmitter, NativeModules } from 'react-native';
import { getConfiguration, setConfiguration, shouldSkipPermissionRequests } from './config';
import type {
  GeolocationConfiguration,
  GeolocationError,
  GeolocationOptions,
  GeolocationResponse,
} from './types';
import { PositionError } from './types';

export { GeolocationOptions, GeolocationResponse, GeolocationError, GeolocationConfiguration, PositionError };

const LINKING_ERROR =
  `The package 'react-native-fitness-geolocation' doesn't seem to be linked. ` +
  'Run pod install (iOS) and rebuild the app.';

const Native = NativeModules.FitnessGeolocation
  ? NativeModules.FitnessGeolocation
  : new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

const emitter = new NativeEventEmitter(Native);

type SuccessCallback = (position: GeolocationResponse) => void;
type ErrorCallback = (error: GeolocationError) => void;

interface WatchEntry {
  success: SuccessCallback;
  error: ErrorCallback;
  motion: boolean;
}

const watchRegistry = new Map<number, WatchEntry>();
let watchSubscription: { remove: () => void } | null = null;
let foregroundSubscription: { remove: () => void } | null = null;
let authSubscription: { remove: () => void } | null = null;
let appStateSubscription: { remove: () => void } | null = null;
let isDraining = false;
let motionWatchCount = 0;

const DRAIN_BATCH = 100;
const DEFAULT_TIMEOUT_MS = 15000;

function positionError(code: number, message: string): GeolocationError {
  return {
    code,
    message,
    PERMISSION_DENIED: PositionError.PERMISSION_DENIED,
    POSITION_UNAVAILABLE: PositionError.POSITION_UNAVAILABLE,
    TIMEOUT: PositionError.TIMEOUT,
  };
}

function payloadToPosition(payload: Record<string, unknown>): GeolocationResponse {
  const coords = (payload.coords as Record<string, unknown>) ?? payload;
  const num = (v: unknown, fallback: number | null = null): number | null => {
    if (v == null) return fallback;
    const n = Number(v);
    return Number.isFinite(n) ? n : fallback;
  };

  return {
    coords: {
      latitude: Number(coords.latitude),
      longitude: Number(coords.longitude),
      altitude: num(coords.altitude),
      accuracy: Number(coords.accuracy ?? 0),
      altitudeAccuracy: num(coords.altitudeAccuracy),
      heading: num(coords.heading),
      speed: num(coords.speed),
    },
    timestamp: Number(payload.timestamp ?? coords.timestamp ?? Date.now()),
  };
}

async function drainNativeQueueToWatches(): Promise<number> {
  if (isDraining || watchRegistry.size === 0) return 0;

  isDraining = true;
  let totalReplayed = 0;

  try {
    let batch: Array<Record<string, unknown>>;
    do {
      batch = await Native.getPendingForJs(DRAIN_BATCH);
      if (!batch?.length) break;

      const deliveredIds: string[] = [];

      for (const payload of batch) {
        const position = payloadToPosition(payload);
        const nativeId = String(payload.id ?? '');

        for (const entry of watchRegistry.values()) {
          try {
            entry.success(position);
          } catch (e) {
            console.warn('[FitnessGeolocation] watch callback error:', e);
          }
        }

        if (nativeId) deliveredIds.push(nativeId);
        totalReplayed++;
      }

      if (deliveredIds.length) {
        await Native.markDelivered(deliveredIds);
      }
    } while (batch.length === DRAIN_BATCH);
  } catch (e) {
    console.warn('[FitnessGeolocation] queue drain failed:', e);
  } finally {
    isDraining = false;
  }

  if (__DEV__ && totalReplayed > 0) {
    console.log(`[FitnessGeolocation] Delivered ${totalReplayed} queued background location(s)`);
  }

  return totalReplayed;
}

function ensureBridgeListeners() {
  if (!watchSubscription) {
    watchSubscription = emitter.addListener(
      'watchPosition',
      (event: {
        watchId: number;
        position?: GeolocationResponse;
        error?: { code: number; message: string };
        nativeId?: string;
      }) => {
        const entry = watchRegistry.get(event.watchId);
        if (!entry) return;

        if (event.error) {
          entry.error(positionError(event.error.code, event.error.message));
        } else if (event.position) {
          entry.success(payloadToPosition(event.position as unknown as Record<string, unknown>));
          if (event.nativeId) {
            Native.markDelivered([event.nativeId]).catch(() => {});
          }
        }
      },
    );
  }

  if (!foregroundSubscription) {
    foregroundSubscription = emitter.addListener('foregroundSync', () => {
      drainNativeQueueToWatches();
    });
  }

  if (!authSubscription) {
    authSubscription = emitter.addListener('authorizationChange', () => {
      if (AppState.currentState === 'active') {
        drainNativeQueueToWatches();
      }
    });
  }

  if (!appStateSubscription) {
    appStateSubscription = AppState.addEventListener('change', state => {
      if (state === 'active') drainNativeQueueToWatches();
    });
  }
}

function requestAuthWithCallbacks(success?: () => void, error?: ErrorCallback): void {
  if (shouldSkipPermissionRequests()) {
    success?.();
    return;
  }
  const level = getConfiguration().authorizationLevel ?? 'whenInUse';
  Native.requestAuthorization(level)
    .then((status: string) => {
      if (status === 'granted') success?.();
      else error?.(positionError(PositionError.PERMISSION_DENIED, 'Permission denied'));
    })
    .catch(() => error?.(positionError(PositionError.PERMISSION_DENIED, 'Permission denied')));
}

function maybeStartMotion(options: GeolocationOptions): boolean {
  if (!options.enableMotion) return false;
  Native.startMotionTracking?.(options.includePedometer ?? false).catch(() => {});
  return true;
}

function stopMotionIfNeeded(): void {
  Native.stopMotionTracking?.().catch(() => {});
}

export const Geolocation = {
  getCurrentPosition(
    success: SuccessCallback,
    error?: ErrorCallback,
    options: GeolocationOptions = {},
  ): void {
    const timeoutMs = options.timeout ?? DEFAULT_TIMEOUT_MS;
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      error?.(positionError(PositionError.TIMEOUT, 'Location request timed out'));
    }, timeoutMs);

    Native.getCurrentPosition(options)
      .then((position: GeolocationResponse) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        success(payloadToPosition(position as unknown as Record<string, unknown>));
      })
      .catch((err: { code?: number; message?: string }) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        error?.(positionError(err?.code ?? PositionError.POSITION_UNAVAILABLE, err?.message ?? 'Position unavailable'));
      });
  },

  watchPosition(
    success: SuccessCallback,
    error?: ErrorCallback,
    options: GeolocationOptions = {},
  ): number {
    ensureBridgeListeners();
    const motion = maybeStartMotion(options);
    if (motion) motionWatchCount++;
    const watchId: number = Native.watchPosition(options);
    watchRegistry.set(watchId, { success, error: error ?? (() => {}), motion });

    if (AppState.currentState === 'active') {
      drainNativeQueueToWatches();
    }

    return watchId;
  },

  clearWatch(watchId: number): void {
    const entry = watchRegistry.get(watchId);
    watchRegistry.delete(watchId);
    Native.clearWatch(watchId);
    if (entry?.motion) {
      motionWatchCount = Math.max(0, motionWatchCount - 1);
      if (motionWatchCount === 0) stopMotionIfNeeded();
    }
    if (watchRegistry.size === 0) {
      Native.purgeDelivered?.().catch(() => {});
    }
  },

  stopObserving(): void {
    watchRegistry.clear();
    Native.stopLocationObserving();
    motionWatchCount = 0;
    Native.stopMotionTracking?.().catch(() => {});
    Native.purgeDelivered?.().catch(() => {});
  },

  requestAuthorization(
    levelOrSuccess?: 'whenInUse' | 'always' | (() => void),
    error?: ErrorCallback,
  ): Promise<string> | void {
    if (typeof levelOrSuccess === 'function') {
      requestAuthWithCallbacks(levelOrSuccess, error);
      return;
    }
    if (shouldSkipPermissionRequests()) {
      return Promise.resolve('granted');
    }
    const level = typeof levelOrSuccess === 'string' ? levelOrSuccess : (getConfiguration().authorizationLevel ?? 'whenInUse');
    return Native.requestAuthorization(level);
  },

  getAuthorizationStatus(): Promise<{ status: string; always: boolean }> {
    return Native.getAuthorizationStatus();
  },

  setRNConfiguration(config: GeolocationConfiguration): void {
    setConfiguration(config);
    if (Native.setConfiguration) {
      Native.setConfiguration(config).catch(() => {});
    }
  },

  syncPendingLocations(): Promise<number> {
    return drainNativeQueueToWatches();
  },

  getQueueSize(): Promise<number> {
    return Native.getQueueSize();
  },

  setTrackingMode(mode: string): Promise<void> {
    return Native.setTrackingMode(mode);
  },

  setActivityPaused(paused: boolean): Promise<void> {
    return Native.setActivityPaused(paused);
  },

  getEngineState(): Promise<Record<string, unknown>> {
    return Native.getEngineState();
  },

  addAuthorizationListener(callback: (status: { status: string }) => void): () => void {
    ensureBridgeListeners();
    const sub = emitter.addListener('authorizationChange', callback);
    return () => sub.remove();
  },
};

export default Geolocation;
