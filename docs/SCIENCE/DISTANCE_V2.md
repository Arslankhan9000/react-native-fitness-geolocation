# DistanceEngine v2 (JS reference)

Implemented in `src/metrics/computeMetricsV2.ts` and surfaced via `src/MetricsV2.ts`.

## Purpose
Compute a **corrected distance** that is robust to:
- GPS jumps / multipath
- timestamp glitches
- low-quality accuracy spikes

## Core formulas
- Segment distance: Haversine \(d\) on WGS84 sphere approximation
- Implied speed: \(v = d / \Delta t\)

## Pipeline
1. Sort points by timestamp
2. Drop invalid timestamps (\(\Delta t \le 0\))
3. Optional accuracy gate (default \( \le 60m\))
4. Outlier rejection by implied speed (default \( \le 12m/s\))
5. Sum remaining segments

## Complexity
- Time: \(O(n)\)
- Space: \(O(1)\) aside from sorted input

## Limitations
- Not map-matched: sharp urban turns may under/over-estimate.
- Spherical approximation: adequate for workout-scale distances, not surveying.

