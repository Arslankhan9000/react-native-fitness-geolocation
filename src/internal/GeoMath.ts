/** Pure-TS geo math — mirrors native GeoMath for tests and lightweight JS checks. */
export type LatLng = { latitude: number; longitude: number };

export function pointInPolygon(lat: number, lng: number, vertices: LatLng[]): boolean {
  const n = vertices.length;
  if (n < 3) return false;
  let inside = false;
  let j = n - 1;
  for (let i = 0; i < n; i++) {
    const yi = vertices[i].latitude;
    const xi = vertices[i].longitude;
    const yj = vertices[j].latitude;
    const xj = vertices[j].longitude;
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi + 1e-12) + xi) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

export function haversineM(
  lat1: number, lng1: number,
  lat2: number, lng2: number,
): number {
  const R = 6_371_000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

export function bearingDegrees(a: LatLng, b: LatLng): number {
  const lat1 = (a.latitude * Math.PI) / 180;
  const lat2 = (b.latitude * Math.PI) / 180;
  const dLon = ((b.longitude - a.longitude) * Math.PI) / 180;
  const y = Math.sin(dLon) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
  const brng = (Math.atan2(y, x) * 180) / Math.PI;
  return (brng + 360) % 360;
}

/**
 * Distance from point to polyline (meters) using segment projection in Equirectangular
 * approximation around the point. Good for short distances (corridor monitoring).
 * Complexity: O(n)
 */
export function distanceToPolylineMeters(p: LatLng, polyline: LatLng[]): number {
  if (polyline.length < 2) return Number.POSITIVE_INFINITY;
  let best = Number.POSITIVE_INFINITY;

  // Local projection scale
  const lat0 = (p.latitude * Math.PI) / 180;
  const cosLat = Math.cos(lat0);
  const R = 6_371_000;

  const px = (p.longitude * Math.PI) / 180 * cosLat * R;
  const py = (p.latitude * Math.PI) / 180 * R;

  for (let i = 1; i < polyline.length; i++) {
    const a = polyline[i - 1];
    const b = polyline[i];
    const ax = (a.longitude * Math.PI) / 180 * cosLat * R;
    const ay = (a.latitude * Math.PI) / 180 * R;
    const bx = (b.longitude * Math.PI) / 180 * cosLat * R;
    const by = (b.latitude * Math.PI) / 180 * R;

    const vx = bx - ax;
    const vy = by - ay;
    const wx = px - ax;
    const wy = py - ay;
    const c1 = vx * wx + vy * wy;
    const c2 = vx * vx + vy * vy;
    const t = c2 > 0 ? Math.max(0, Math.min(1, c1 / c2)) : 0;
    const cx = ax + t * vx;
    const cy = ay + t * vy;
    const dx = px - cx;
    const dy = py - cy;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d < best) best = d;
  }

  return best;
}
