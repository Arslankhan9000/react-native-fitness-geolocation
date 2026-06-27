import { distanceToPolylineMeters } from '../src/internal/GeoMath';

describe('Spatial MVP', () => {
  it('distanceToPolylineMeters is near zero on the route', () => {
    const route = [
      { latitude: 37, longitude: -122 },
      { latitude: 37.001, longitude: -122.001 },
      { latitude: 37.002, longitude: -122.002 },
    ];
    const p = { latitude: 37.001, longitude: -122.001 };
    const d = distanceToPolylineMeters(p, route);
    expect(d).toBeLessThan(5);
  });
});

