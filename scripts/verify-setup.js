#!/usr/bin/env node
/**
 * Verify platform setup for react-native-fitness-geolocation
 * Run from app root: npx react-native-fitness-geolocation verify-setup
 */

const fs = require('fs');
const path = require('path');

const appRoot = process.cwd();
const issues = [];
const ok = [];
const packageAndroidManifest = path.join(__dirname, '..', 'android', 'src', 'main', 'AndroidManifest.xml');
const packageManifest = fs.existsSync(packageAndroidManifest)
  ? fs.readFileSync(packageAndroidManifest, 'utf8')
  : '';

function check(name, pass, fix) {
  if (pass) ok.push(`✅ ${name}`);
  else issues.push(`❌ ${name}\n   → ${fix}`);
}

function findInfoPlist(dir, depth = 0) {
  if (depth > 4) return null;
  const direct = path.join(dir, 'Info.plist');
  if (fs.existsSync(direct)) return direct;
  if (!fs.existsSync(dir)) return null;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && entry.name !== 'Pods' && entry.name !== 'build') {
      const found = findInfoPlist(path.join(dir, entry.name), depth + 1);
      if (found) return found;
    }
  }
  return null;
}

const plistPath = findInfoPlist(path.join(appRoot, 'ios'));

if (plistPath) {
  const plist = fs.readFileSync(plistPath, 'utf8');
  check('iOS NSLocationWhenInUseUsageDescription', plist.includes('NSLocationWhenInUseUsageDescription'),
    'Add NSLocationWhenInUseUsageDescription to Info.plist — see docs/SETUP.md');
  check('iOS NSLocationAlwaysAndWhenInUseUsageDescription', plist.includes('NSLocationAlwaysAndWhenInUseUsageDescription'),
    'Add NSLocationAlwaysAndWhenInUseUsageDescription for background tracking');
  check('iOS UIBackgroundModes location', /UIBackgroundModes[\s\S]*location/.test(plist),
    'Add <string>location</string> to UIBackgroundModes array');
  check('iOS NSMotionUsageDescription (optional)', plist.includes('NSMotionUsageDescription'),
    'Add NSMotionUsageDescription for MotionEngine auto-pause');
} else {
  issues.push('⚠️  iOS Info.plist not found — skip if Android-only');
}

const manifestPath = path.join(appRoot, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
if (fs.existsSync(manifestPath)) {
  const manifest = fs.readFileSync(manifestPath, 'utf8');
  const mergedSource = `${manifest}\n${packageManifest}`;
  check('Android ACCESS_FINE_LOCATION', mergedSource.includes('ACCESS_FINE_LOCATION'),
    'Add ACCESS_FINE_LOCATION permission');
  check('Android ACCESS_BACKGROUND_LOCATION', mergedSource.includes('ACCESS_BACKGROUND_LOCATION'),
    'Add ACCESS_BACKGROUND_LOCATION for background tracking (API 29+)');
  check('Android FOREGROUND_SERVICE_LOCATION', mergedSource.includes('FOREGROUND_SERVICE_LOCATION'),
    'Add FOREGROUND_SERVICE_LOCATION for Android 14+');
  check('Android FitnessLocationService', mergedSource.includes('FitnessLocationService'),
    'Ensure the package AndroidManifest.xml is included by React Native autolinking');
  check('Android ACTIVITY_RECOGNITION (optional)', mergedSource.includes('ACTIVITY_RECOGNITION'),
    'Add ACTIVITY_RECOGNITION for MotionEngine auto-pause');
} else {
  issues.push('⚠️  AndroidManifest.xml not found — skip if iOS-only');
}

console.log('\nreact-native-fitness-geolocation — Setup Verification\n');
ok.forEach(l => console.log(l));
issues.forEach(l => console.log(l));

const failures = issues.filter(i => i.startsWith('❌'));
if (failures.length) {
  console.log('\nSee docs/SETUP.md for copy-paste snippets.\n');
  process.exit(1);
} else {
  console.log('\nAll required checks passed.\n');
}
