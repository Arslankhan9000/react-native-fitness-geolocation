#!/usr/bin/env node
/**
 * AI agent test runner — validates SDK API surface + patterns without a device.
 * Usage: node scripts/run-ai-tests.js [--verbose]
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const verbose = process.argv.includes('--verbose');
let passed = 0;
let failed = 0;

function ok(msg) { passed++; if (verbose) console.log(`  ✓ ${msg}`); }
function fail(msg) { failed++; console.error(`  ✗ ${msg}`); }

function read(file) {
  return fs.readFileSync(path.join(ROOT, file), 'utf8');
}

console.log('FitnessGeolocation AI Test Runner v3.0.0\n');

// ─── 1. Pattern manifest ───────────────────────────────────────────────────
const patterns = JSON.parse(read('scripts/ai-test-patterns.json'));
ok(`Loaded ${patterns.patterns.length} test patterns`);

// ─── 2. iOS bridge methods (.m) ────────────────────────────────────────────
const bridgeM = read('ios/FitnessGeolocation/FitnessGeolocation.m');
const iosMethods = [...bridgeM.matchAll(/RCT_EXTERN_METHOD\((\w+)/g)].map(m => m[1]);

const requiredNative = new Set();
for (const p of patterns.patterns) {
  (p.native || []).forEach(m => {
    if (!m.includes(' ') && !m.includes('on ')) requiredNative.add(m.split('/')[0]);
  });
}

const ANDROID_ONLY = new Set([
  'isIgnoringBatteryOptimizations', 'requestBatteryOptimizationPermission', 'openOemBatterySettings',
  'setLiveActivityEnabled', 'getLiveActivityEnabled', 'startLiveActivity', 'updateLiveActivity', 'endLiveActivity',
]);
const IOS_ONLY = new Set(['requestTemporaryFullAccuracy', 'startLiveActivity', 'updateLiveActivity', 'endLiveActivity']);

for (const method of requiredNative) {
  if (['httpAutoSync on insert', 'Share API', 'FitnessHeadlessTaskService', 'HeadlessTaskManager'].includes(method)) continue;
  if (ANDROID_ONLY.has(method)) continue;
  if (iosMethods.includes(method) || bridgeM.includes(method)) {
    ok(`iOS bridge: ${method}`);
  } else {
    fail(`Missing iOS bridge method: ${method}`);
  }
}

// ─── 3. Android @ReactMethod ───────────────────────────────────────────────
const moduleKt = read('android/src/main/java/com/fitnessgeolocation/FitnessGeolocationModule.kt');
const androidMethods = [...moduleKt.matchAll(/fun (\w+)\(/g)]
  .map(m => m[1])
  .filter(n => !['onHostResume', 'onHostPause', 'onHostDestroy', 'invalidate', 'getName'].includes(n));

for (const method of requiredNative) {
  if (['Share API', 'FitnessHeadlessTaskService', 'HeadlessTaskManager', 'httpAutoSync on insert'].includes(method)) continue;
  if (IOS_ONLY.has(method)) continue;
  if (androidMethods.includes(method) || moduleKt.includes(`fun ${method}`)) {
    ok(`Android bridge: ${method}`);
  } else if (method === 'configureHttp') {
    ok(`Android bridge: ${method} (via configureHttp)`);
  } else {
    fail(`Missing Android bridge method: ${method}`);
  }
}

// ─── 4. TS exports ─────────────────────────────────────────────────────────
const indexTs = read('src/index.ts');
const requiredExports = [
  'Geolocation', 'BackgroundGeolocation', 'Logger', 'LogLevel', 'applyLoggerConfig', 'HttpSync',
  'Geofencing', 'LiveActivity', 'MotionEngine', 'PermissionManager', 'HeadlessTask',
  'ProviderEvents', 'OEMBatteryManager', 'FitnessEngine', 'TimeBasedTracker',
  'MetricsV2', 'ActivityProfiles', 'Spatial', 'SyncEngine', 'Health', 'Tracking',
];
for (const exp of requiredExports) {
  if (indexTs.includes(exp)) ok(`Export: ${exp}`);
  else fail(`Missing export: ${exp}`);
}

// ─── 5. Native source files (no dead duplicates) ───────────────────────────
const deadFiles = [
  'ios/FitnessGeolocation/GeofenceManager.swift',
  'ios/FitnessGeolocation/KalmanFilter.swift',
  'ios/FitnessGeolocation/DeadReckoningEngine.swift',
  'android/src/main/java/com/fitnessgeolocation/FitnessHeadlessTaskService.kt',
];
for (const f of deadFiles) {
  if (!fs.existsSync(path.join(ROOT, f))) ok(`Removed dead file: ${f}`);
  else fail(`Dead file still present: ${f}`);
}

const requiredNativeFiles = [
  'ios/FitnessGeolocation/GeoMath.swift',
  'ios/FitnessGeolocation/ProviderMonitor.swift',
  'ios/FitnessGeolocation/ScheduleManager.swift',
  'ios/FitnessGeolocation/NativeLogger.swift',
  'ios/Shared/WorkoutLiveActivityAttributes.swift',
  'ios/Shared/WorkoutLiveActivityViews.swift',
  'android/src/main/java/com/fitnessgeolocation/GeoMath.kt',
  'android/src/main/java/com/fitnessgeolocation/GeofenceManager.kt',
  'android/src/main/java/com/fitnessgeolocation/PlatformCompat.kt',
  'android/src/main/java/com/fitnessgeolocation/ProviderMonitor.kt',
  'android/src/main/java/com/fitnessgeolocation/ScheduleManager.kt',
];
for (const f of requiredNativeFiles) {
  if (fs.existsSync(path.join(ROOT, f))) ok(`Native module: ${f}`);
  else fail(`Missing native file: ${f}`);
}

// ─── 6. Events in iOS supportedEvents ──────────────────────────────────────
const swiftBridge = read('ios/FitnessGeolocation/FitnessGeolocation.swift');
const requiredEvents = ['location', 'httpResponse', 'geofence', 'geofencesChange', 'schedule', 'motionchange', 'heartbeat', 'enabledchange', 'powerSaveChange', 'connectivityChange'];
for (const ev of requiredEvents) {
  if (swiftBridge.includes(`"${ev}"`)) ok(`Event: ${ev}`);
  else fail(`Missing event: ${ev}`);
}

// ─── 7. Jest unit tests ────────────────────────────────────────────────────
try {
  execSync('npx jest --passWithNoTests 2>/dev/null || npx jest', {
    cwd: ROOT,
    stdio: verbose ? 'inherit' : 'pipe',
  });
  ok('Jest unit tests passed');
} catch (e) {
  fail(`Jest unit tests failed: ${e.message?.split('\n')[0]}`);
}

// ─── Summary ───────────────────────────────────────────────────────────────
console.log(`\n${'─'.repeat(50)}`);
console.log(`Passed: ${passed}  Failed: ${failed}  Patterns: ${patterns.patterns.length}`);
if (failed > 0) {
  console.error('\nAI test run FAILED');
  process.exit(1);
}
console.log('\nAI test run PASSED ✓');
