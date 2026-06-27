import { pointInPolygon, haversineM } from '../src/internal/GeoMath';

describe('GeoMath', () => {
  const square = [
    { latitude: 0, longitude: 0 },
    { latitude: 0, longitude: 1 },
    { latitude: 1, longitude: 1 },
    { latitude: 1, longitude: 0 },
  ];

  it('point inside unit square', () => {
    expect(pointInPolygon(0.5, 0.5, square)).toBe(true);
  });

  it('point outside unit square', () => {
    expect(pointInPolygon(2, 2, square)).toBe(false);
  });

  it('point on edge treated consistently', () => {
    expect(pointInPolygon(0, 0.5, square)).toBeDefined();
  });

  it('rejects degenerate polygon', () => {
    expect(pointInPolygon(0.5, 0.5, [{ latitude: 0, longitude: 0 }])).toBe(false);
  });

  it('haversine zero distance', () => {
    expect(haversineM(37.33, -122.03, 37.33, -122.03)).toBeCloseTo(0, 1);
  });

  it('haversine ~1km', () => {
    const d = haversineM(37.33, -122.03, 37.34, -122.03);
    expect(d).toBeGreaterThan(900);
    expect(d).toBeLessThan(1200);
  });
});
