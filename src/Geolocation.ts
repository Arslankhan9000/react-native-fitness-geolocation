import { AppState, NativeEventEmitter, NativeModules, Platform } from 'react-native';
import { getConfiguration, setConfiguration, shouldSkipPermissionRequests } from './config';
import type {
  BackgroundGeolocationConfig,
  BackgroundGeolocationState,
  GeolocationConfiguration,
  GeolocationDiagnosticEvent,
  GeolocationError,
  GeolocationOptions,
  GeolocationResponse,
  LocationSubscription,
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

type SuccessCallback = (position: GeolocationResponse) => void | Promise<void>;
type ErrorCallback = (error: GeolocationError) => void;

interface WatchEntry {
  success: SuccessCallback;
  error: ErrorCallback;
  motion: boolean;
}

const watchRegistry = new Map<number, WatchEntry>();
const inFlightNativeIds = new Set<string>();
let watchSubscription: { remove: () => void } | null = null;
let foregroundSubscription: { remove: () => void } | null = null;
let authSubscription: { remove: () => void } | null = null;
let diagnosticSubscription: { remove: () => void } | null = null;
let appStateSubscription: { remove: () => void } | null = null;
let isDraining = false;
let motionWatchCount = 0;
let backgroundConfig: BackgroundGeolocationConfig = {};
let backgroundWatchId: number | null = null;
let backgroundConfigured = false;

const locationListeners = new Set<SuccessCallback>();
const locationErrorListeners = new Set<ErrorCallback>();
const diagnosticListeners = new Set<(event: GeolocationDiagnosticEvent) => void>();
const jsDiagnostics: GeolocationDiagnosticEvent[] = [];

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

function reportJsDiagnostic(event: string, data: Record<string, unknown> = {}): void {
  const row: GeolocationDiagnosticEvent = {
    event,
    platform: Platform.OS === 'android' ? 'android' : 'ios',
    timestamp: Date.now(),
    layer: 'js',
    ...data,
  };
  jsDiagnostics.push(row);
  if (jsDiagnostics.length > 300) {
    jsDiagnostics.splice(0, jsDiagnostics.length - 300);
  }
  for (const listener of diagnosticListeners) {
    try {
      listener(row);
    } catch {}
  }
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
  reportJsDiagnostic('queue-drain-start', { watchCount: watchRegistry.size });

  try {
    let batch: Array<Record<string, unknown>>;
    do {
      batch = await Native.getPendingForJs(DRAIN_BATCH);
      if (!batch?.length) break;

      const deliveredIds: string[] = [];

      for (const payload of batch) {
        const position = payloadToPosition(payload);
        const nativeId = String(payload.id ?? '');
        if (nativeId && inFlightNativeIds.has(nativeId)) continue;
        let deliveredToAll = true;

        for (const entry of watchRegistry.values()) {
          try {
            await entry.success(position);
          } catch (e) {
            deliveredToAll = false;
            reportJsDiagnostic('callback-failed', {
              nativeId,
              message: e instanceof Error ? e.message : String(e),
            });
            console.warn('[FitnessGeolocation] watch callback error:', e);
          }
        }

        if (nativeId && deliveredToAll) deliveredIds.push(nativeId);
        totalReplayed++;
      }

      if (deliveredIds.length) {
        await Native.markDelivered(deliveredIds);
        reportJsDiagnostic('queue-ack', { count: deliveredIds.length });
      }
    } while (batch.length === DRAIN_BATCH);
  } catch (e) {
    reportJsDiagnostic('queue-drain-failed', {
      message: e instanceof Error ? e.message : String(e),
    });
    console.warn('[FitnessGeolocation] queue drain failed:', e);
  } finally {
    isDraining = false;
    reportJsDiagnostic('queue-drain-end', { replayed: totalReplayed });
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
          if (event.nativeId) inFlightNativeIds.add(event.nativeId);
          Promise.resolve(entry.success(payloadToPosition(event.position as unknown as Record<string, unknown>)))
            .then(() => {
              if (event.nativeId) {
                Native.markDelivered([event.nativeId])
                  .then(() => reportJsDiagnostic('live-ack', { nativeId: event.nativeId }))
                  .catch((e: unknown) => {
                    reportJsDiagnostic('live-ack-failed', {
                      nativeId: event.nativeId,
                      message: e instanceof Error ? e.message : String(e),
                    });
                  });
              }
            })
            .catch(e => {
              reportJsDiagnostic('callback-failed', {
                nativeId: event.nativeId,
                message: e instanceof Error ? e.message : String(e),
              });
              console.warn('[FitnessGeolocation] watch callback error:', e);
            })
            .finally(() => {
              if (event.nativeId) inFlightNativeIds.delete(event.nativeId);
            });
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

  if (!diagnosticSubscription) {
    diagnosticSubscription = emitter.addListener(
      'diagnostic',
      (event: GeolocationDiagnosticEvent) => {
        for (const listener of diagnosticListeners) {
          try {
            listener(event);
          } catch {}
        }
      },
    );
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

async function notifyBackgroundLocation(position: GeolocationResponse): Promise<void> {
  if (locationListeners.size === 0) {
    throw new Error('No BackgroundGeolocation.onLocation subscriber');
  }
  for (const listener of locationListeners) {
    await listener(position);
  }
}

function notifyBackgroundError(error: GeolocationError): void {
  for (const listener of locationErrorListeners) {
    try {
      listener(error);
    } catch (e) {
      console.warn('[FitnessGeolocation] onLocation error callback failed:', e);
    }
  }
}

async function getBackgroundState(): Promise<BackgroundGeolocationState> {
  const [engine, auth] = await Promise.all([
    Native.getEngineState(),
    Native.getAuthorizationStatus(),
  ]);

  return {
    ...(engine as Record<string, unknown>),
    enabled: backgroundWatchId != null || Boolean((engine as { isWatching?: boolean }).isWatching),
    configured: backgroundConfigured,
    authorization: auth.status,
    always: auth.always,
  } as BackgroundGeolocationState;
}

export const Geolocation = {
  async ready(config: BackgroundGeolocationConfig = {}): Promise<BackgroundGeolocationState> {
    backgroundConfig = {
      enableHighAccuracy: true,
      distanceFilter: 0,
      pausesLocationUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
      trackingMode: 'fitness',
      authorizationLevel: 'always',
      stopOnTerminate: false,
      ...backgroundConfig,
      ...config,
    };
    backgroundConfigured = true;

    this.setRNConfiguration(backgroundConfig);
    await Native.setConfiguration?.(backgroundConfig).catch(() => {});

    if (backgroundConfig.startOnReady) {
      await this.start();
    }

    return getBackgroundState();
  },

  async start(options: GeolocationOptions = {}): Promise<BackgroundGeolocationState> {
    ensureBridgeListeners();
    if (!backgroundConfigured) {
      await this.ready();
    }

    if (backgroundWatchId == null) {
      backgroundWatchId = this.watchPosition(
        position => notifyBackgroundLocation(position),
        error => notifyBackgroundError(error),
        { ...backgroundConfig, ...options },
      );
    }

    return getBackgroundState();
  },

  async stop(): Promise<BackgroundGeolocationState> {
    if (backgroundWatchId != null) {
      this.clearWatch(backgroundWatchId);
      backgroundWatchId = null;
    }
    await this.syncPendingLocations();
    return getBackgroundState();
  },

  onLocation(success: SuccessCallback, error?: ErrorCallback): LocationSubscription {
    locationListeners.add(success);
    if (error) locationErrorListeners.add(error);
    return {
      remove: () => {
        locationListeners.delete(success);
        if (error) locationErrorListeners.delete(error);
      },
    };
  },

  onHeartbeat(callback: (state: BackgroundGeolocationState) => void | Promise<void>): LocationSubscription {
    ensureBridgeListeners();
    const sub = emitter.addListener('foregroundSync', async () => {
      await callback(await getBackgroundState());
    });
    return { remove: () => sub.remove() };
  },

  async changePace(isMoving: boolean): Promise<void> {
    await Native.setActivityPaused(!isMoving);
  },

  sync(): Promise<number> {
    return drainNativeQueueToWatches();
  },

  getState(): Promise<BackgroundGeolocationState> {
    return getBackgroundState();
  },

  onDiagnostic(callback: (event: GeolocationDiagnosticEvent) => void): LocationSubscription {
    ensureBridgeListeners();
    diagnosticListeners.add(callback);
    return { remove: () => diagnosticListeners.delete(callback) };
  },

  async getDiagnostics(): Promise<GeolocationDiagnosticEvent[]> {
    const nativeRows: GeolocationDiagnosticEvent[] = await Native.getDiagnostics();
    return [...nativeRows, ...jsDiagnostics].sort((a, b) => a.timestamp - b.timestamp);
  },

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
    const willBeEmpty = watchRegistry.size <= 1 && watchRegistry.has(watchId);

    // Stop native GPS immediately when last watch ends — do not wait for queue drain.
    if (willBeEmpty) {
      watchRegistry.delete(watchId);
      Native.clearWatch(watchId);
      if (entry?.motion) {
        motionWatchCount = 0;
        stopMotionIfNeeded();
      } else {
        motionWatchCount = 0;
        Native.stopMotionTracking?.().catch(() => {});
      }
      Native.stopLocationObserving();
      drainNativeQueueToWatches().finally(() => {
        Native.purgeDelivered?.().catch(() => {});
      });
      return;
    }

    const finishClear = () => {
      watchRegistry.delete(watchId);
      Native.clearWatch(watchId);
      if (entry?.motion) {
        motionWatchCount = Math.max(0, motionWatchCount - 1);
        if (motionWatchCount === 0) stopMotionIfNeeded();
      }
    };

    if (!entry) {
      finishClear();
      return;
    }

    drainNativeQueueToWatches().finally(finishClear);
  },

  stopObserving(): void {
    watchRegistry.clear();
    motionWatchCount = 0;
    Native.stopLocationObserving();
    Native.stopMotionTracking?.().catch(() => {});
    drainNativeQueueToWatches().finally(() => {
      Native.purgeDelivered?.().catch(() => {});
    });
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
