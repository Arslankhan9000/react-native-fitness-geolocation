import { NativeEventEmitter } from 'react-native';
import type { MotionActivityType } from './types';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();
const emitter = new NativeEventEmitter(Native);

export interface MotionActivityEvent {
  activity: MotionActivityType;
  confidence: number;
}

export interface MotionStepsEvent {
  steps: number;
  distanceM: number;
}

export interface AutoPauseEvent {
  reason: 'stationary' | 'gps' | 'manual';
}

/**
 * Native motion intelligence — CMMotionActivityManager (iOS) / ActivityRecognition (Android).
 * Runs independently of JS; emits auto-pause/resume like Strava/Nike RC.
 */
export const MotionEngine = {
  start(options: { includePedometer?: boolean } = {}): void {
    Native.startMotionTracking(options.includePedometer ?? false);
    ensureListeners();
  },

  stop(): void {
    Native.stopMotionTracking();
  },

  configureAutoPause(enabled: boolean, delaySeconds = 45): Promise<void> {
    return Native.configureAutoPause(enabled, delaySeconds);
  },

  onActivityChange(listener: (event: MotionActivityEvent) => void): () => void {
    ensureListeners();
    const sub = emitter.addListener('motionActivity', listener);
    return () => sub.remove();
  },

  onStepsUpdate(listener: (event: MotionStepsEvent) => void): () => void {
    ensureListeners();
    const sub = emitter.addListener('motionSteps', listener);
    return () => sub.remove();
  },

  onAutoPause(listener: (event: AutoPauseEvent) => void): () => void {
    ensureListeners();
    const sub = emitter.addListener('autoPause', listener);
    return () => sub.remove();
  },

  onAutoResume(listener: (event: { reason: string }) => void): () => void {
    ensureListeners();
    const sub = emitter.addListener('autoResume', listener);
    return () => sub.remove();
  },
};

let listenersReady = false;

function ensureListeners() {
  listenersReady = true;
}

export default MotionEngine;
