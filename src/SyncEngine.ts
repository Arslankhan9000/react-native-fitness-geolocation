import { AppState } from 'react-native';
import type { HttpConfig } from './types';
import { getFitnessGeolocationNative } from './native/getNativeModule';
import { diagnosticsEngine } from './engines/DiagnosticsEngine';

const Native = getFitnessGeolocationNative();

export interface SyncEngineConfig extends HttpConfig {
  /** Max retry attempts per run */
  maxAttempts?: number;
  /** Base backoff milliseconds */
  backoffBaseMs?: number;
  /** Max backoff milliseconds */
  backoffMaxMs?: number;
}

/**
 * SyncEngine v2 (JS scheduler facade).
 *
 * - Native remains the source of truth for background-safe HTTP uploads.
 * - This engine adds non-blocking scheduling + retry/backoff semantics for foreground and
 *   for callers that want deterministic control.
 */
export class SyncEngine {
  private config: Required<Pick<SyncEngineConfig, 'maxAttempts' | 'backoffBaseMs' | 'backoffMaxMs'>> & HttpConfig = {
    url: '',
    maxAttempts: 5,
    backoffBaseMs: 2000,
    backoffMaxMs: 60000,
  };

  private inFlight = false;
  private attempt = 0;
  private timer: any = null;
  private appStateSub: { remove: () => void } | null = null;

  configure(config: SyncEngineConfig): void {
    this.config = {
      ...this.config,
      ...config,
      maxAttempts: config.maxAttempts ?? this.config.maxAttempts,
      backoffBaseMs: config.backoffBaseMs ?? this.config.backoffBaseMs,
      backoffMaxMs: config.backoffMaxMs ?? this.config.backoffMaxMs,
    };
    Native.configureHttp?.(config as any);
    diagnosticsEngine.log('info', 'sync_configured', { url: config.url });
  }

  start(): void {
    if (this.appStateSub) return;
    this.appStateSub = AppState.addEventListener('change', (s) => {
      if (s === 'active') this.trigger('foreground');
    }) as any;
  }

  stop(): void {
    this.appStateSub?.remove();
    this.appStateSub = null;
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  async trigger(reason: string = 'manual'): Promise<void> {
    if (!this.config.url) return;
    if (this.inFlight) return;
    this.inFlight = true;

    try {
      diagnosticsEngine.log('info', 'sync_trigger', { reason, attempt: this.attempt });
      await Native.httpSync?.();
      this.attempt = 0;
      diagnosticsEngine.log('info', 'sync_success', { reason });
    } catch (e: any) {
      this.attempt++;
      diagnosticsEngine.log('warn', 'sync_failure', { attempt: this.attempt, error: String(e?.message ?? e) });
      if (this.attempt <= (this.config.maxAttempts ?? 5)) {
        const delay = Math.min(
          (this.config.backoffBaseMs ?? 2000) * Math.pow(2, Math.max(0, this.attempt - 1)),
          this.config.backoffMaxMs ?? 60000,
        );
        this.timer = setTimeout(() => {
          this.timer = null;
          this.inFlight = false;
          void this.trigger('retry');
        }, delay);
        return;
      }
    } finally {
      this.inFlight = false;
    }
  }
}

export const syncEngine = new SyncEngine();
export default syncEngine;

