import type { BackgroundGeolocationConfig } from '../types';

type AnyConfig = Partial<BackgroundGeolocationConfig> & Record<string, unknown>;

function assignDefined<T extends Record<string, unknown>>(target: T, source: Record<string, unknown> | undefined): T {
  if (!source) return target;
  for (const [k, v] of Object.entries(source)) {
    if (v !== undefined) (target as any)[k] = v;
  }
  return target;
}

/**
 * Flattens Transistorsoft-style compound config groups into our existing flat config.
 *
 * Precedence:
 * - nested groups override root keys (eg `http.url` > `url`)
 * - `logger` is preserved (used by applyLoggerConfig), but nested objects are removed
 *   so the resulting object is safe to pass to native `setConfiguration`.
 */
export function normalizeConfig(input: Partial<BackgroundGeolocationConfig> = {}): BackgroundGeolocationConfig {
  const cfg: AnyConfig = { ...(input as AnyConfig) };

  // Apply nested groups (override root)
  assignDefined(cfg, cfg.geolocation as Record<string, unknown> | undefined);
  assignDefined(cfg, cfg.http as Record<string, unknown> | undefined);
  assignDefined(cfg, cfg.activity as Record<string, unknown> | undefined);
  assignDefined(cfg, cfg.persistence as Record<string, unknown> | undefined);
  assignDefined(cfg, cfg.app as Record<string, unknown> | undefined);

  // Remove nested objects so native receives a flat map.
  delete cfg.geolocation;
  delete cfg.http;
  delete cfg.activity;
  delete cfg.persistence;
  delete cfg.app;

  return cfg as BackgroundGeolocationConfig;
}

