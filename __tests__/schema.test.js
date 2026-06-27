const fs = require('fs');
const path = require('path');

describe('Native storage schema', () => {
  it('iOS LocationDatabase defines vNext tables', () => {
    const p = path.join(__dirname, '../ios/FitnessGeolocation/LocationDatabase.swift');
    const s = fs.readFileSync(p, 'utf8');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS diagnostics_timeline');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS motion_events');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS geofence_events');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS sync_queue');
  });

  it('Android LocationDatabase defines vNext tables', () => {
    const p = path.join(__dirname, '../android/src/main/java/com/fitnessgeolocation/LocationDatabase.kt');
    const s = fs.readFileSync(p, 'utf8');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS diagnostics_timeline');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS motion_events');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS geofence_events');
    expect(s).toContain('CREATE TABLE IF NOT EXISTS sync_queue');
    expect(s).toContain('SQLiteOpenHelper(context, DB_NAME, null, 6)');
  });

  it('Geofence scaling active-set logic exists', () => {
    const fs = require('fs');
    const path = require('path');
    const ios = fs.readFileSync(path.join(__dirname, '../ios/FitnessGeolocation/LocationEngine.swift'), 'utf8');
    const android = fs.readFileSync(path.join(__dirname, '../android/src/main/java/com/fitnessgeolocation/GeofenceManager.kt'), 'utf8');
    expect(ios).toContain('maxActiveCircularGeofences');
    expect(ios).toContain('refreshActiveCircularGeofences');
    expect(android).toContain('MAX_ACTIVE_CIRCULAR');
    expect(android).toContain('refreshActiveCircular');
    expect(android).toContain('updateDeviceLocation');
  });
});

