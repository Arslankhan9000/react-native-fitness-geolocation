import { NativeEventEmitter, NativeModules } from 'react-native';
import type {
  Geofence,
  GeofenceEvent,
  GeofencesChangeEvent,
  LocationSubscription,
} from './types';

const Native = NativeModules.FitnessGeolocation;
const emitter = new NativeEventEmitter(Native);
const TAG = 'FitnessGeoGeofence';

type GeofenceCallback = (event: GeofenceEvent) => void;
type GeofencesChangeCallback = (event: GeofencesChangeEvent) => void;

/**
 * Geofencing API — monitor circular geographic regions.
 *
 * iOS supports up to 20 geofences simultaneously.
 * Android supports up to 100.
 *
 * The native engine automatically manages proximity — only geofences
 * near the device are actively monitored, while the full list is
 * stored in the SQLite database.
 */
export class Geofencing {
  private geofenceListeners = new Set<GeofenceCallback>();
  private geofencesChangeListeners = new Set<GeofencesChangeCallback>();
  private geofenceSub: { remove: () => void } | null = null;
  private geofencesChangeSub: { remove: () => void } | null = null;
  private listenerCount = 0;

  private ensureSubscriptions(): void {
    if (!this.geofenceSub) {
      this.geofenceSub = emitter.addListener('geofence', (event: GeofenceEvent) => {
        for (const cb of this.geofenceListeners) {
          try { cb(event); } catch {}
        }
      });
    }
    if (!this.geofencesChangeSub) {
      this.geofencesChangeSub = emitter.addListener(
        'geofencesChange',
        (event: GeofencesChangeEvent) => {
          for (const cb of this.geofencesChangeListeners) {
            try { cb(event); } catch {}
          }
        },
      );
    }
  }

  /**
   * Add a single geofence to monitor.
   */
  async addGeofence(geofence: Geofence): Promise<boolean> {
    try {
      const result = await Native.addGeofence?.({
        identifier: geofence.identifier,
        latitude: geofence.latitude,
        longitude: geofence.longitude,
        radius: geofence.radius,
        notifyOnEntry: geofence.notifyOnEntry ?? true,
        notifyOnExit: geofence.notifyOnExit ?? true,
        notifyOnDwell: geofence.notifyOnDwell ?? false,
        loiteringDelayMs: geofence.loiteringDelayMs ?? 30000,
        extras: geofence.extras ?? {},
      });
      if (__DEV__) {
        Native.devLog?.('info', TAG, 'geofence_added', { identifier: geofence.identifier });
      }
      return result === true;
    } catch (error) {
      console.error(`[${TAG}] Failed to add geofence:`, error);
      return false;
    }
  }

  /**
   * Add multiple geofences at once (faster than individual calls).
   */
  async addGeofences(geofences: Geofence[]): Promise<boolean> {
    try {
      const result = await Native.addGeofences?.(geofences);
      return result === true;
    } catch (error) {
      console.error(`[${TAG}] Failed to add geofences:`, error);
      return false;
    }
  }

  /**
   * Remove a geofence by identifier.
   */
  async removeGeofence(identifier: string): Promise<boolean> {
    try {
      const result = await Native.removeGeofence?.(identifier);
      return result === true;
    } catch (error) {
      console.error(`[${TAG}] Failed to remove geofence:`, error);
      return false;
    }
  }

  /**
   * Remove all geofences, or specific ones by identifiers.
   */
  async removeGeofences(identifiers?: string[]): Promise<boolean> {
    try {
      const result = await Native.removeGeofences?.(identifiers);
      return result === true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Get all geofences currently in the database.
   */
  async getGeofences(): Promise<Geofence[]> {
    try {
      return await Native.getGeofences?.() ?? [];
    } catch {
      return [];
    }
  }

  /**
   * Check if a geofence with the given identifier exists.
   */
  async geofenceExists(identifier: string): Promise<boolean> {
    try {
      return await Native.geofenceExists?.(identifier) === true;
    } catch {
      return false;
    }
  }

  /**
   * Subscribe to geofence transition events (ENTER/EXIT/DWELL).
   */
  onGeofence(callback: GeofenceCallback): LocationSubscription {
    this.ensureSubscriptions();
    this.geofenceListeners.add(callback);
    return {
      remove: () => {
        this.geofenceListeners.delete(callback);
        this.cleanupIfNeeded();
      },
    };
  }

  /**
   * Subscribe to changes in the actively monitored geofence list.
   * Fired when geofences are added/removed from the active set
   * based on device proximity.
   */
  onGeofencesChange(callback: GeofencesChangeCallback): LocationSubscription {
    this.ensureSubscriptions();
    this.geofencesChangeListeners.add(callback);
    return {
      remove: () => {
        this.geofencesChangeListeners.delete(callback);
        this.cleanupIfNeeded();
      },
    };
  }

  private cleanupIfNeeded(): void {
    if (this.geofenceListeners.size === 0 && this.geofencesChangeListeners.size === 0) {
      this.geofenceSub?.remove();
      this.geofenceSub = null;
      this.geofencesChangeSub?.remove();
      this.geofencesChangeSub = null;
    }
  }
}

export const geofencing = new Geofencing();
export default Geofencing;
