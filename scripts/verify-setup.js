#!/usr/bin/env node
/**
 * Verify platform setup for @micim/react-native-geolocation
 * Run from app root: node node_modules/@micim/react-native-geolocation/scripts/verify-setup.js
 */

const fs = require('fs');
const path = require('path');

const appRoot = process.cwd();
const issues = [];
const ok = [];

function check(name, pass, fix) {
  if (pass) ok.push(`✅ ${name}`);
  else issues.push(`❌ ${name}\n   → ${fix}`);
}

// iOS Info.plist
const plistPaths = [
  path.join(appRoot, 'ios', 'myfitnesscoach', 'Info.plist'),
  path.join(appRoot, 'ios', 'Info.plist'),
];
const plistPath = plistPaths.find(p => fs.existsSync(p));

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
  issues.push('❌ iOS Info.plist not found — skip if Android-only');
}

// Android Manifest
const manifestPath = path.join(appRoot, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
if (fs.existsSync(manifestPath)) {
  const manifest = fs.readFileSync(manifestPath, 'utf8');
  check('Android ACCESS_FINE_LOCATION', manifest.includes('ACCESS_FINE_LOCATION'),
    'Add ACCESS_FINE_LOCATION permission');
  check('Android ACCESS_BACKGROUND_LOCATION', manifest.includes('ACCESS_BACKGROUND_LOCATION'),
    'Add ACCESS_BACKGROUND_LOCATION for background tracking');
  check('Android FOREGROUND_SERVICE_LOCATION', manifest.includes('FOREGROUND_SERVICE_LOCATION'),
    'Add FOREGROUND_SERVICE_LOCATION for Android 14+');
  check('Android ACTIVITY_RECOGNITION', manifest.includes('ACTIVITY_RECOGNITION'),
    'Add ACTIVITY_RECOGNITION for MotionEngine');
} else {
  issues.push('❌ AndroidManifest.xml not found — skip if iOS-only');
}

console.log('\n@micim/geo — Setup Verification\n');
ok.forEach(l => console.log(l));
issues.forEach(l => console.log(l));

if (issues.length) {
  console.log('\nSee docs/SETUP.md for copy-paste snippets.\n');
  process.exit(1);
} else {
  console.log('\nAll checks passed.\n');
}
