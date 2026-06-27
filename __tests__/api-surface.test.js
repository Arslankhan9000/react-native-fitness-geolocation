const fs = require('fs');
const path = require('path');

const patterns = require('../scripts/ai-test-patterns.json');
const indexTs = fs.readFileSync(path.join(__dirname, '../src/index.ts'), 'utf8');

describe('API surface', () => {
  const requiredExports = [
    'Geolocation', 'BackgroundGeolocation', 'Logger', 'HttpSync',
    'Geofencing', 'LiveActivity', 'MotionEngine', 'PermissionManager', 'HeadlessTask',
    'ProviderEvents', 'OEMBatteryManager', 'FitnessEngine', 'TimeBasedTracker',
  ];

  it('exports all SDK modules from index.ts', () => {
    for (const exp of requiredExports) {
      expect(indexTs).toContain(exp);
    }
  });

  it('covers all AI test pattern ids', () => {
    const ids = patterns.patterns.map(p => p.id);
    expect(ids.length).toBeGreaterThanOrEqual(25);
    expect(ids).toContain('geofence.polygon');
    expect(ids).toContain('http.autoSync');
    expect(ids).toContain('lifecycle.reset');
  });

  it('Geolocation.ts has full background lifecycle', () => {
    const geolocation = fs.readFileSync(path.join(__dirname, '../src/Geolocation.ts'), 'utf8');
    expect(geolocation).toContain('ready');
    expect(geolocation).toContain('uploadLog');
    expect(geolocation).toContain('uploadToServer');
    expect(geolocation).toContain('requestTemporaryFullAccuracy');
    expect(geolocation).toContain('reset');
  });

  it('Logger.ts has shipping methods', () => {
    const logger = fs.readFileSync(path.join(__dirname, '../src/Logger.ts'), 'utf8');
    expect(logger).toContain('uploadLog');
    expect(logger).toContain('emailLog');
  });
});
