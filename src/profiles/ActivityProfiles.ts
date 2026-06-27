import type { ActivityOptions } from '../types';

export type ActivityProfileId =
  | 'walking'
  | 'running'
  | 'hiking'
  | 'cycling'
  | 'driving'
  | 'fleet';

export interface ActivityProfile {
  id: ActivityProfileId;
  displayName: string;
  /** Default strategy values applied when the caller doesn't override them. */
  defaults: Partial<ActivityOptions>;
  /** Scientific/engineering rationale (short) */
  rationale: string;
  /** Known limitations / edge cases */
  limitations: string[];
}

/**
 * Activity profiles define strategy defaults (GPS/motion/battery) without hardcoding
 * logic throughout the engine. This is the routing layer for vNext.
 *
 * These are intentionally conservative defaults; apps can override per-session.
 */
export const ActivityProfiles: Record<ActivityProfileId, ActivityProfile> = {
  walking: {
    id: 'walking',
    displayName: 'Walking',
    defaults: {
      activityType: 'walking',
      intervalMs: 5000,
      adaptiveInterval: true,
      stationaryIntervalMs: 45000,
      maxAccuracy: 60,
      autoPause: true,
      autoPauseDelaySeconds: 60,
    },
    rationale: 'Lower cadence movement; allow slightly looser accuracy and longer intervals for battery efficiency.',
    limitations: ['Urban canyons may require higher accuracy for route fidelity.'],
  },
  running: {
    id: 'running',
    displayName: 'Running',
    defaults: {
      activityType: 'running',
      intervalMs: 3000,
      adaptiveInterval: true,
      stationaryIntervalMs: 30000,
      maxAccuracy: 40,
      autoPause: true,
      autoPauseDelaySeconds: 45,
    },
    rationale: 'Higher cadence; prioritize route fidelity and pacing stability.',
    limitations: ['Treadmill/indoor runs need sensor fusion beyond GPS (future).'],
  },
  hiking: {
    id: 'hiking',
    displayName: 'Hiking',
    defaults: {
      activityType: 'walking',
      intervalMs: 6000,
      adaptiveInterval: true,
      stationaryIntervalMs: 60000,
      maxAccuracy: 80,
      autoPause: true,
      autoPauseDelaySeconds: 90,
    },
    rationale: 'Slow, stop-and-go; tolerate longer stationary windows to avoid false pauses at viewpoints.',
    limitations: ['Forest/mountain multipath increases GPS noise; corrected distance is important.'],
  },
  cycling: {
    id: 'cycling',
    displayName: 'Cycling',
    defaults: {
      activityType: 'cycling',
      intervalMs: 2000,
      adaptiveInterval: true,
      stationaryIntervalMs: 30000,
      maxAccuracy: 50,
      autoPause: true,
      autoPauseDelaySeconds: 30,
    },
    rationale: 'Higher speed; shorter interval helps cornering fidelity. Auto-pause is tighter.',
    limitations: ['Downhill speeds may trigger outlier filters; tune max implied speed per route.'],
  },
  driving: {
    id: 'driving',
    displayName: 'Driving',
    defaults: {
      activityType: 'driving',
      trackingMode: 'navigation',
      intervalMs: 5000,
      adaptiveInterval: true,
      stationaryIntervalMs: 60000,
      maxAccuracy: 100,
      autoPause: false,
      autoResume: false,
    },
    rationale: 'Vehicle tracking values stability and battery. Auto-pause is usually undesirable for navigation traces.',
    limitations: ['Precise turn-by-turn needs map-matching (Spatial Intelligence todo).'],
  },
  fleet: {
    id: 'fleet',
    displayName: 'Fleet',
    defaults: {
      activityType: 'driving',
      trackingMode: 'navigation',
      intervalMs: 10000,
      adaptiveInterval: true,
      stationaryIntervalMs: 120000,
      maxAccuracy: 150,
      autoPause: false,
      autoResume: false,
    },
    rationale: 'Enterprise fleet use cases prefer fewer wakeups and controlled battery usage; sampling is policy-driven.',
    limitations: ['Background restrictions vary by OEM; health checks should guide operators.'],
  },
};

export function getActivityProfile(id: ActivityProfileId): ActivityProfile {
  return ActivityProfiles[id];
}

export function resolveProfileDefaults(options: ActivityOptions): ActivityOptions {
  const id = (options.activityType as ActivityProfileId) || 'running';
  const profile = ActivityProfiles[id] ?? ActivityProfiles.running;
  return { ...profile.defaults, ...options } as ActivityOptions;
}

