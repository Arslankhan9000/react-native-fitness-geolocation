#!/usr/bin/env node
/**
 * Replay simulator (JS) — deterministic pipeline runner.
 *
 * Input: JSON trace
 *   [
 *     { "latitude": 37.0, "longitude": -122.0, "accuracy": 5, "timestamp": 1000 },
 *     ...
 *   ]
 *
 * Output: MetricsV2 summary JSON.
 *
 * This is the first shipping version of replay; native replay hooks can be added later.
 */

const fs = require('fs');
const path = require('path');

function toRad(deg) { return (deg * Math.PI) / 180; }
function distance2dMeters(a, b) {
  const R = 6371000;
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
  return R * c;
}

function computeMetricsV2(sessionId, points, opts = {}) {
  const maxAccuracyM = opts.maxAccuracyM ?? 60;
  const maxImpliedSpeedMps = opts.maxImpliedSpeedMps ?? 12;
  const movingSpeedThresholdMps = opts.movingSpeedThresholdMps ?? 0.5;

  const cleaned = points
    .filter(p => Number.isFinite(p.latitude) && Number.isFinite(p.longitude) && Number.isFinite(p.timestamp))
    .sort((a, b) => a.timestamp - b.timestamp);

  let total = 0, corrected = 0, moving = 0, maxSpeed = 0, dropped = 0;
  const notes = [];

  if (cleaned.length < 2) {
    return { sessionId, pointCount: cleaned.length, totalDistance2d: 0, correctedDistance2d: 0, movingDistance2d: 0, maxSpeedMps: 0, averageSpeedMps: 0, droppedPoints: 0, notes: ['INSUFFICIENT_POINTS'] };
  }

  let prev = cleaned[0];
  for (let i = 1; i < cleaned.length; i++) {
    const cur = cleaned[i];
    const dt = (cur.timestamp - prev.timestamp) / 1000;
    if (!Number.isFinite(dt) || dt <= 0) { dropped++; continue; }
    const seg = distance2dMeters(prev, cur);
    total += seg;
    const implied = seg / dt;
    const prevAcc = prev.accuracy ?? 0;
    const curAcc = cur.accuracy ?? 0;
    const accOk = (prevAcc <= 0 || prevAcc <= maxAccuracyM) && (curAcc <= 0 || curAcc <= maxAccuracyM);
    if (!accOk || implied > maxImpliedSpeedMps) { dropped++; prev = cur; continue; }
    corrected += seg;
    if (implied >= movingSpeedThresholdMps) moving += seg;
    if (implied > maxSpeed) maxSpeed = implied;
    prev = cur;
  }
  const elapsedS = (cleaned[cleaned.length - 1].timestamp - cleaned[0].timestamp) / 1000;
  const avg = elapsedS > 0 ? corrected / elapsedS : 0;
  if (dropped > 0) notes.push('OUTLIERS_DROPPED');
  return { sessionId, pointCount: cleaned.length, totalDistance2d: total, correctedDistance2d: corrected, movingDistance2d: moving, maxSpeedMps: maxSpeed, averageSpeedMps: avg, droppedPoints: dropped, notes };
}

function main() {
  const file = process.argv[2];
  if (!file) {
    console.error('Usage: node scripts/replay.js <trace.json>');
    process.exit(2);
  }
  const p = path.resolve(process.cwd(), file);
  const raw = fs.readFileSync(p, 'utf8');
  const points = JSON.parse(raw);
  const out = computeMetricsV2(path.basename(file), points);
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
}

main();

