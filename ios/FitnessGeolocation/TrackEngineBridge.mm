/**
 * TrackEngineBridge.mm — ObjC++ implementation of the C++ bridge.
 *
 * This file MUST have the .mm extension so Clang compiles it as
 * Objective-C++ (mixing ObjC and C++).
 */

#import "TrackEngineBridge.h"
#include "TrackEngine.h"   // Full C++ engine

// ── TEFixResult ─────────────────────────────────────────────────────────────

@implementation TEFixResult {
    teng::SessionEngine::FixResult _r;
}

- (instancetype)initWithResult:(const teng::SessionEngine::FixResult &)r {
    if ((self = [super init])) {
        _r = r;
    }
    return self;
}

- (double)filteredLat               { return _r.filtered_lat; }
- (double)filteredLng               { return _r.filtered_lng; }
- (double)totalDistanceM            { return _r.total_distance_m; }
- (double)elapsedS                  { return _r.elapsed_s; }
- (double)speedKmh                  { return _r.speed_kmh; }
- (double)paceMinPerKm              { return _r.pace_min_per_km; }
- (BOOL)accepted                    { return _r.accepted ? YES : NO; }
- (BOOL)shouldUpdateLiveActivity    { return _r.should_update_live_activity ? YES : NO; }

- (NSString *)paceStr {
    return [NSString stringWithUTF8String:_r.pace_str];
}

@end

// ── TrackEngineBridge ────────────────────────────────────────────────────────

@implementation TrackEngineBridge {
    teng::SessionEngine _engine;
}

+ (instancetype)shared {
    static TrackEngineBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TrackEngineBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        // SessionEngine is zero-initialized via C++ default constructor
    }
    return self;
}

- (void)startSession:(double)unixTimeS liveActivityInterval:(double)laIntervalS {
    _engine.start(unixTimeS, laIntervalS);
}

- (void)stopSession {
    _engine.stop();
}

- (TEFixResult *)ingestLat:(double)lat
                       lng:(double)lng
                  accuracy:(double)accuracy
               unixTimeS:(double)unixTimeS
                 speedMps:(double)speedMps {
    auto r = _engine.ingest(lat, lng, accuracy, unixTimeS, speedMps);
    return [[TEFixResult alloc] initWithResult:r];
}

- (double)totalDistanceM {
    return _engine.dist.get();
}

- (NSUInteger)ringBufferCount {
    return (NSUInteger)_engine.ring.count();
}

- (BOOL)isActive {
    return _engine.active ? YES : NO;
}

- (void)setMaxAccuracyM:(float)maxAccuracyM {
    _engine.loc_filter.max_accuracy_m = maxAccuracyM;
}

- (void)setMaxSpeedMps:(float)maxSpeedMps {
    _engine.loc_filter.max_speed_mps = maxSpeedMps;
}

@end
