import { AppState, NativeEventEmitter, NativeModules } from 'react-native';
import type {
  GeolocationConfiguration,
  GeolocationError,
  GeolocationOptions,
  GeolocationResponse,
} from './types';

export { GeolocationOptions, GeolocationResponse, GeolocationError, GeolocationConfiguration };

const LINKING_ERROR =
  `The package '@micim/geo' doesn't seem to be linked. ` +
  'Run pod install (iOS) and rebuild the app.';

const Native = NativeModules.MicimGeolocation
  ? NativeModules.MicimGeolocation
  : new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

const emitter = new NativeEventEmitter(Native);

type SuccessCallback = (position: GeolocationResponse) => void;
type ErrorCallback = (error: GeolocationError) => void;

interface WatchEntry {
  success: SuccessCallback;
  error: ErrorCallback;
}

const watchRegistry = new Map<number, WatchEntry>();
let watchSubscription: { remove: () => void } | null = null;
let foregroundSubscription: { remove: () => void } | null = null;
let appStateSubscription: { remove: () => void } | null = null;
let isDraining = false;

const DRAIN_BATCH = 100;

function positionError(code: number, message: string): GeolocationError {
  return {
    code,
    message,
    PERMISSION_DENIED: 1,
    POSITION_UNAVAILABLE: 2,
    TIMEOUT: 3,
  };
}

function payloadToPosition(payload: Record<string, unknown>): GeolocationResponse {
  return {
    coords: {
      latitude: Number(payload.latitude),
      longitude: Number(payload.longitude),
      altitude: Number(payload.altitude ?? 0),
      accuracy: Number(payload.accuracy ?? 0),
      heading: Number(payload.heading ?? 0),
      speed: Number(payload.speed ?? 0),
    },
    timestamp: Number(payload.timestamp),
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
            console.warn('[MicimGeolocation] watch callback error:', e);
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
    console.warn('[MicimGeolocation] drain failed:', e);
  } finally {
    isDraining = false;
  }

  if (totalReplayed > 0) {
    console.log(`[MicimGeolocation] Synced ${totalReplayed} background points to Realm`);
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
          entry.success(event.position);
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

  if (!appStateSubscription) {
    appStateSubscription = AppState.addEventListener('change', state => {
      if (state === 'active') drainNativeQueueToWatches();
    });
  }
}

function requestAuthWithCallbacks(success?: () => void, error?: ErrorCallback): void {
  Native.requestAuthorization('whenInUse')
    .then((status: string) => {
      if (status === 'granted') success?.();
      else error?.(positionError(1, 'Permission denied'));
    })
    .catch(() => error?.(positionError(1, 'Permission denied')));
}

export const Geolocation = {
  getCurrentPosition(
    success: SuccessCallback,
    error?: ErrorCallback,
    options: GeolocationOptions = {},
  ): void {
    Native.getCurrentPosition(options)
      .then((position: GeolocationResponse) => success(position))
      .catch((err: { code?: number; message?: string }) => {
        error?.(positionError(err?.code ?? 2, err?.message ?? 'Position unavailable'));
      });
  },

  watchPosition(
    success: SuccessCallback,
    error?: ErrorCallback,
    options: GeolocationOptions = {},
  ): number {
    ensureBridgeListeners();
    // Auto-start native motion engine (Strava-class auto-pause) — no app code needed
    Native.startMotionTracking?.(false).catch(() => {});
    const watchId: number = Native.watchPosition(options);
    watchRegistry.set(watchId, { success, error: error ?? (() => {}) });

    if (AppState.currentState === 'active') {
      drainNativeQueueToWatches();
    }

    return watchId;
  },

  clearWatch(watchId: number): void {
    watchRegistry.delete(watchId);
    Native.clearWatch(watchId);
    if (watchRegistry.size === 0) {
      Native.stopMotionTracking?.().catch(() => {});
      Native.purgeDelivered?.().catch(() => {});
    }
  },

  stopObserving(): void {
    watchRegistry.clear();
    Native.stopObserving();
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
    const level = typeof levelOrSuccess === 'string' ? levelOrSuccess : 'whenInUse';
    return Native.requestAuthorization(level);
  },

  getAuthorizationStatus(): Promise<{ status: string; always: boolean }> {
    return Native.getAuthorizationStatus();
  },

  setRNConfiguration(_config: GeolocationConfiguration): void {},

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
};

export default Geolocation;
