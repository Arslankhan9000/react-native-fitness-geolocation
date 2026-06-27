import { Platform } from 'react-native';
import { getFitnessGeolocationNative } from '../native/getNativeModule';

export type DiagnosticsLevel = 'debug' | 'info' | 'warn' | 'error';

export interface DiagnosticsTimelineRow {
  timestamp: number;
  platform: 'ios' | 'android';
  layer: 'native' | 'js';
  level: DiagnosticsLevel;
  event: string;
  data?: Record<string, unknown>;
}

const Native = getFitnessGeolocationNative();

/**
 * DiagnosticsEngine
 * - JS-side structured timeline (for explainability)
 * - Mirrors important lifecycle events even when native logs are unavailable
 *
 * Native already persists/returns diagnostics via `getDiagnostics()`; this engine
 * adds a JS timeline overlay and a single merge point for consumers.
 */
class DiagnosticsEngine {
  private jsTimeline: DiagnosticsTimelineRow[] = [];
  private maxRows = 500;

  log(level: DiagnosticsLevel, event: string, data: Record<string, unknown> = {}): void {
    const row: DiagnosticsTimelineRow = {
      timestamp: Date.now(),
      platform: Platform.OS === 'android' ? 'android' : 'ios',
      layer: 'js',
      level,
      event,
      data,
    };
    this.jsTimeline.push(row);
    if (this.jsTimeline.length > this.maxRows) {
      this.jsTimeline.splice(0, this.jsTimeline.length - this.maxRows);
    }
    // Best-effort native dev log (no-op if not implemented)
    try {
      Native.devLog?.(level, 'DiagnosticsEngine', event, data);
    } catch {
      // ignore
    }
  }

  async getTimeline(): Promise<DiagnosticsTimelineRow[]> {
    let nativeRows: any[] = [];
    try {
      nativeRows = (await Native.getDiagnostics?.()) ?? [];
    } catch {
      nativeRows = [];
    }

    const normalizedNative = nativeRows
      .map((r) => ({
        timestamp: typeof r.timestamp === 'number' ? r.timestamp : Date.now(),
        platform: (r.platform === 'android' || r.platform === 'ios')
          ? r.platform
          : (Platform.OS === 'android' ? 'android' : 'ios'),
        layer: 'native',
        level: (r.level as DiagnosticsLevel) ?? 'info',
        event: r.event ?? 'native',
        data: (r.data as Record<string, unknown>) ?? r,
      })) as DiagnosticsTimelineRow[];

    return [...normalizedNative, ...this.jsTimeline].sort((a, b) => a.timestamp - b.timestamp);
  }

  clearJsTimeline(): void {
    this.jsTimeline = [];
  }
}

export const diagnosticsEngine = new DiagnosticsEngine();
export default diagnosticsEngine;

