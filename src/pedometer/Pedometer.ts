import { AppState, NativeEventEmitter, Platform, type AppStateStatus, type EmitterSubscription } from 'react-native';
import { PedometerError } from './errors';
import { callNative, getPedometerNative } from './nativeBridge';
import { EMPTY_STEP_EVENT, parseStepEvent } from './parseStepEvent';
import { PedometerPermission } from './PedometerPermission';
import { createStepCountFilter } from './StepCountFilter';
import type {
  PedometerPermissionStatus,
  PedometerStartOptions,
  PedometerStepEvent,
  PedometerSupportResult,
} from './types';

type StepListener = (event: PedometerStepEvent) => void;

let running = false;
let appStateSub: { remove: () => void } | null = null;
let eventSub: EmitterSubscription | null = null;
let emitter: NativeEventEmitter | null = null;
const listeners = new Set<StepListener>();
let filterFn: ((data: PedometerStepEvent) => PedometerStepEvent | null) | null = null;

function getEmitter(): NativeEventEmitter | null {
  if (emitter) return emitter;
  const native = getPedometerNative();
  if (!native) return null;
  try {
    emitter = new NativeEventEmitter(native as never);
    return emitter;
  } catch {
    return null;
  }
}

function ensureBridge(): void {
  if (eventSub) return;
  const em = getEmitter();
  if (!em) return;
  eventSub = em.addListener('pedometerUpdate', (raw: Record<string, unknown>) => {
    try {
      const event = parseStepEvent(raw);
      if (event.isRunning) running = true;
      const filtered = filterFn ? filterFn(event) : event;
      if (!filtered) return;
      listeners.forEach(fn => {
        try {
          fn(filtered);
        } catch {
          /* listener isolation */
        }
      });
    } catch {
      /* malformed native payload */
    }
  });
}

function ensureAppStateBridge(): void {
  if (appStateSub) return;
  appStateSub = AppState.addEventListener('change', (state: AppStateStatus) => {
    if (state === 'active') {
      void Pedometer.syncFromNative();
    }
  });
}

async function readSnapshot(): Promise<PedometerStepEvent> {
  const snap = await callNative<Record<string, unknown>>('pedometerGetSnapshot', {}, n =>
    n.pedometerGetSnapshot!() as Promise<Record<string, unknown>>,
  );
  return parseStepEvent(snap);
}

/**
 * Passive pedometer — independent lifecycle from GPS.
 *
 * Default install (`react-native-fitness-geolocation`) includes everything.
 * Subpath `react-native-fitness-geolocation/pedometer` tree-shakes JS only.
 */
export const Pedometer = {
  async isSupported(): Promise<PedometerSupportResult> {
    if (!getPedometerNative()) {
      return {
        supported: false,
        granted: false,
        status: 'unknown',
        platform: Platform.OS === 'ios' ? 'ios' : 'android',
      };
    }
    return PedometerPermission.getSupport();
  },

  async requestPermission(): Promise<PedometerPermissionStatus> {
    return PedometerPermission.request();
  },

  /**
   * Align JS state with native (call on launch, resume, after kill).
   */
  async syncFromNative(): Promise<PedometerStepEvent> {
    const snap = await readSnapshot();
    running = snap.isRunning;
    if (running) {
      ensureBridge();
      ensureAppStateBridge();
      getPedometerNative()?.pedometerOnAppForeground?.();
    }
    return snap;
  },

  async start(options: PedometerStartOptions = {}): Promise<PedometerStepEvent> {
    if (!getPedometerNative()) {
      throw new PedometerError(
        'NATIVE_UNAVAILABLE',
        'Pedometer native module not linked. Rebuild after pod install.',
      );
    }

    const support = await PedometerPermission.getSupport();
    if (!support.supported) {
      throw new PedometerError('NOT_SUPPORTED', 'Step counting is not supported on this device');
    }

    if (!support.granted) {
      const status = await PedometerPermission.request();
      if (status !== 'granted' && Platform.OS === 'android') {
        throw new PedometerError('PERMISSION_DENIED', 'Activity recognition permission denied');
      }
    }

    // Idempotent — native returns current session if already running
    const existing = await readSnapshot();
    if (existing.isRunning && running) {
      return existing;
    }

    const useFilter = options.filterLiveUpdates !== false;
    filterFn = useFilter
      ? createStepCountFilter({ minimumStepIntervalMs: options.minimumStepIntervalMs })
      : null;

    ensureBridge();
    ensureAppStateBridge();

    const snap = await callNative<Record<string, unknown>>('pedometerStart', {}, n =>
      n.pedometerStart!(options.sessionId ?? null) as Promise<Record<string, unknown>>,
    );
    const parsed = parseStepEvent(snap);
    if (!parsed.isRunning && parsed.steps === 0 && !existing.isRunning) {
      throw new PedometerError('NATIVE_FAILED', 'Failed to start pedometer session');
    }

    running = true;
    return parsed;
  },

  async stop(): Promise<PedometerStepEvent> {
    if (!getPedometerNative()) {
      running = false;
      return EMPTY_STEP_EVENT;
    }

    const snap = await callNative<Record<string, unknown>>('pedometerStop', {}, n =>
      n.pedometerStop!() as Promise<Record<string, unknown>>,
    );
    running = false;
    filterFn = null;
    return parseStepEvent(snap);
  },

  async getSnapshot(): Promise<PedometerStepEvent> {
    return readSnapshot();
  },

  /** @deprecated Use syncFromNative() */
  async restore(): Promise<PedometerStepEvent | null> {
    const snap = await this.syncFromNative();
    return snap.isRunning ? snap : null;
  },

  onStepUpdate(listener: StepListener): { remove: () => void } {
    ensureBridge();
    listeners.add(listener);
    return { remove: () => listeners.delete(listener) };
  },

  isRunning(): boolean {
    return running;
  },
};

export { PedometerError, isPedometerError } from './errors';
export type { PedometerStepEvent, PedometerStartOptions, PedometerSupportResult };
