import { Platform } from 'react-native';
import type { HttpConfig, HttpEvent, LocationSubscription } from './types';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();
const TAG = 'FitnessGeoHttp';

type HttpCallback = (event: HttpEvent) => void;

/**
 * Native HTTP auto-sync for background location uploads.
 *
 * Instead of sending each point to your server via JS (which won't work
 * when the app is killed on Android), configure the native layer to
 * upload directly from the native process.
 *
 * On Android headless mode, this completely replaces the need for a
 * running JS context — locations are collected by the foreground service
 * and uploaded directly to your server.
 */
export class HttpSync {
  private httpListeners = new Set<HttpCallback>();
  private configured = false;

  /**
   * Configure HTTP auto-sync.
   * Must be called before tracking starts to take full effect.
   */
  configure(config: HttpConfig): void {
    if (!config.url) {
      console.warn(`[${TAG}] No URL provided — HTTP sync disabled`);
      return;
    }

    const nativeConfig: Record<string, unknown> = {
      url: config.url,
      method: config.method ?? 'POST',
      headers: config.headers ?? {},
      autoSync: config.autoSync ?? true,
      batchSync: config.batchSync ?? true,
      batchSize: config.batchSize ?? 100,
      maxDaysToPersist: config.maxDaysToPersist ?? 7,
      retryCount: config.retryCount ?? 3,
      params: config.params ?? {},
    };
    if (config.locationTemplate) {
      nativeConfig.locationTemplate = config.locationTemplate;
    }

    Native.configureHttp?.(nativeConfig);
    this.configured = true;

    if (__DEV__) {
      console.log(`[${TAG}] Configured: ${config.url}`);
      Native.devLog?.('info', TAG, 'configured', { url: config.url });
    }
  }

  /**
   * Whether HTTP auto-sync is configured.
   */
  get isConfigured(): boolean {
    return this.configured;
  }

  /**
   * Manually trigger a sync of all pending locations to the server.
   * Returns the locations that were synced.
   */
  async sync(): Promise<Record<string, unknown>[]> {
    try {
      const result = await Native.httpSync?.();
      if (__DEV__) {
        console.log(`[${TAG}] Manual sync completed: ${result?.length ?? 0} locations`);
      }
      return result ?? [];
    } catch (error) {
      console.error(`[${TAG}] Sync failed:`, error);
      return [];
    }
  }

  /**
   * Subscribe to HTTP response events from the server.
   */
  onHttp(callback: HttpCallback): LocationSubscription {
    this.httpListeners.add(callback);

    // Ensure native listener is set up
    Native.addHttpListener?.();

    return {
      remove: () => {
        this.httpListeners.delete(callback);
        if (this.httpListeners.size === 0) {
          Native.removeHttpListener?.();
        }
      },
    };
  }

  /** Internal: called by native event emitter */
  _handleHttpEvent(event: HttpEvent): void {
    for (const cb of this.httpListeners) {
      try { cb(event); } catch {}
    }
  }

  /**
   * Destroy all pending locations in the database without uploading.
   */
  async destroyLocations(): Promise<void> {
    await Native.destroyLocations?.();
  }

  /**
   * Get count of pending locations.
   */
  async getCount(): Promise<number> {
    try {
      return await Native.getCount?.() ?? 0;
    } catch {
      return 0;
    }
  }
}

export const httpSync = new HttpSync();
export default HttpSync;
