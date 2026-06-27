import { getFitnessGeolocationNative } from './native/getNativeModule';
import { diagnosticsEngine } from './engines/DiagnosticsEngine';
import { distanceToPolylineMeters, bearingDegrees } from './internal/GeoMath';

const Native = getFitnessGeolocationNative();

export interface LatLng {
  latitude: number;
  longitude: number;
}

export interface RouteConfig {
  /** Ordered polyline points (WGS84). */
  route: LatLng[];
  /** Corridor radius in meters. */
  corridorRadiusM?: number;
  /** Heading tolerance for wrong-direction (degrees). */
  wrongDirectionToleranceDeg?: number;
}

export type SpatialEvent =
  | { type: 'inCorridor'; distanceToRouteM: number }
  | { type: 'outOfCorridor'; distanceToRouteM: number }
  | { type: 'offRoute'; distanceToRouteM: number }
  | { type: 'wrongDirection'; headingDeg: number; expectedBearingDeg: number; deltaDeg: number }
  | { type: 'returnedToRoute'; distanceToRouteM: number };

/**
 * Spatial Intelligence MVP (JS implementation).
 *
 * - Corridor monitoring (in/out)
 * - Off-route detection
 * - Wrong-direction heuristic
 *
 * Events are logged to DiagnosticsEngine (and best-effort native log) so they remain
 * available offline and in headless contexts.
 */
class SpatialEngine {
  private config: Required<RouteConfig> | null = null;
  private wasOut = false;

  setRoute(config: RouteConfig): void {
    this.config = {
      route: config.route,
      corridorRadiusM: config.corridorRadiusM ?? 30,
      wrongDirectionToleranceDeg: config.wrongDirectionToleranceDeg ?? 70,
    };
    this.wasOut = false;
    diagnosticsEngine.log('info', 'spatial_route_set', {
      points: this.config.route.length,
      corridorRadiusM: this.config.corridorRadiusM,
    });
  }

  clearRoute(): void {
    this.config = null;
    this.wasOut = false;
    diagnosticsEngine.log('info', 'spatial_route_cleared', {});
  }

  /**
   * Evaluate a location point against the configured route.
   * Returns 0..n events for this point.
   */
  evaluate(point: LatLng & { headingDeg?: number | null }): SpatialEvent[] {
    const cfg = this.config;
    if (!cfg || cfg.route.length < 2) return [];

    const distanceToRouteM = distanceToPolylineMeters(point, cfg.route);
    const events: SpatialEvent[] = [];

    const inCorridor = distanceToRouteM <= cfg.corridorRadiusM;
    if (inCorridor) {
      events.push({ type: 'inCorridor', distanceToRouteM });
      if (this.wasOut) events.push({ type: 'returnedToRoute', distanceToRouteM });
      this.wasOut = false;
    } else {
      events.push({ type: 'outOfCorridor', distanceToRouteM });
      if (distanceToRouteM > cfg.corridorRadiusM * 2) {
        events.push({ type: 'offRoute', distanceToRouteM });
      }
      this.wasOut = true;
    }

    // Wrong-direction heuristic: compare current heading to route local bearing near start.
    if (point.headingDeg != null && cfg.route.length >= 2) {
      const expected = bearingDegrees(cfg.route[0], cfg.route[1]);
      const delta = smallestAngleDelta(point.headingDeg, expected);
      if (Math.abs(delta) >= cfg.wrongDirectionToleranceDeg) {
        events.push({
          type: 'wrongDirection',
          headingDeg: point.headingDeg,
          expectedBearingDeg: expected,
          deltaDeg: delta,
        });
      }
    }

    // Persist/log
    for (const e of events) {
      diagnosticsEngine.log('info', 'spatial_event', e as any);
      try {
        Native.log?.('INFO', `spatial:${e.type}`, e as any);
      } catch {
        // ignore
      }
    }

    return events;
  }
}

function smallestAngleDelta(a: number, b: number): number {
  let d = ((a - b + 540) % 360) - 180;
  if (!Number.isFinite(d)) d = 0;
  return d;
}

export const Spatial = new SpatialEngine();
export default Spatial;

