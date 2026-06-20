import { NativeEventEmitter, NativeModules } from 'react-native';
import type {
  ProviderChangeEvent,
  ConnectivityChangeEvent,
  LocationSubscription,
  SensorState,
} from './types';

const Native = NativeModules.FitnessGeolocation;
const emitter = new NativeEventEmitter(Native);
const TAG = 'FitnessGeoProvider';

type ProviderCallback = (event: ProviderChangeEvent) => void;
type ConnectivityCallback = (event: ConnectivityChangeEvent) => void;

/**
 * Provider & Power Save event monitoring.
 *
 * Tracks changes in location provider state (GPS on/off, authorization),
 * network connectivity, and power saving mode — essential for knowing
 * why tracking might stop unexpectedly.
 */
export const ProviderEvents = {
  // ─── Provider State ─────────────────────────────────────────────────────────

  /**
   * Subscribe to changes in location provider state.
   * Fires when: GPS turns on/off, location permissions change,
   * accuracy authorization changes (iOS 14+).
   */
  onProviderChange(callback: ProviderCallback): LocationSubscription {
    const sub = emitter.addListener('providerChange', callback);
    return { remove: () => sub.remove() };
  },

  /**
   * Get the current state of location providers.
   */
  async getProviderState(): Promise<ProviderChangeEvent> {
    try {
      return await Native.getProviderState?.() ?? {
        enabled: false,
        status: 'not_determined',
      };
    } catch {
      return { enabled: false, status: 'not_determined' };
    }
  },

  // ─── Power Save ─────────────────────────────────────────────────────────────

  /**
   * Subscribe to changes in OS power saving mode.
   */
  onPowerSaveChange(callback: (enabled: boolean) => void): LocationSubscription {
    const sub = emitter.addListener('powerSaveChange', (event: { enabled: boolean }) => {
      callback(event.enabled);
    });
    return { remove: () => sub.remove() };
  },

  /**
   * Check if the device is currently in power saving mode.
   */
  async isPowerSaveMode(): Promise<boolean> {
    try {
      return await Native.isPowerSaveMode?.() === true;
    } catch {
      return false;
    }
  },

  // ─── Connectivity ───────────────────────────────────────────────────────────

  /**
   * Subscribe to network connectivity changes.
   */
  onConnectivityChange(callback: ConnectivityCallback): LocationSubscription {
    const sub = emitter.addListener('connectivityChange', callback);
    return { remove: () => sub.remove() };
  },

  // ─── Sensors ────────────────────────────────────────────────────────────────

  /**
   * Get available motion sensors on the device.
   */
  async getSensors(): Promise<SensorState> {
    try {
      return await Native.getSensors?.() ?? {
        accelerometer: false,
        gyroscope: false,
        magnetometer: false,
      };
    } catch {
      return { accelerometer: false, gyroscope: false, magnetometer: false };
    }
  },

  // ─── Device Info ────────────────────────────────────────────────────────────

  /**
   * Get device information.
   */
  async getDeviceInfo(): Promise<Record<string, unknown>> {
    try {
      return await Native.getDeviceInfo?.() ?? {};
    } catch {
      return {};
    }
  },
};

export default ProviderEvents;
