#!/usr/bin/env node
/**
 * Build lib/ when devDependencies are installed (npm publish / package dev).
 * Skips gracefully when linked from an app via file: without bob installed.
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const libEntry = path.join(__dirname, '..', 'lib', 'commonjs', 'index.js');
if (fs.existsSync(libEntry)) {
  process.exit(0);
}

try {
  require.resolve('react-native-builder-bob/package.json');
  execSync('bob build', { stdio: 'inherit', cwd: path.join(__dirname, '..') });
} catch {
  console.warn(
    '[react-native-fitness-geolocation] lib/ not built — Metro will use src/ via react-native field.',
  );
}
