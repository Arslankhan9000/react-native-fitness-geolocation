/**
 * TrackEngineBridge.h — ObjC interface over the C++ TrackEngine.
 *
 * Import this header in the Swift bridging header so that Swift code can
 * call the C++ engine without touching C++ directly.
 *
 * Usage from Swift:
 *
 *   let result = TrackEngineBridge.shared.ingest(
 *       lat: loc.coordinate.latitude,
 *       lng: loc.coordinate.longitude,
 *       accuracy: loc.horizontalAccuracy,
 *       unixTimeS: loc.timestamp.timeIntervalSince1970,
 *       speedMps: loc.speed
 *   )
 *   if result.accepted {
 *       // use result.filteredLat/Lng, result.totalDistanceM, result.paceStr, etc.
 *   }
 */

#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Mirror of teng::SessionEngine::FixResult.
 * All values are safe to read from Swift.
 */
@interface TEFixResult : NSObject

/// Filtered (Kalman-smoothed) latitude. Valid only when accepted == YES.
@property (nonatomic, readonly) double filteredLat;
/// Filtered longitude.
@property (nonatomic, readonly) double filteredLng;
/// Total session distance (metres) including this fix.
@property (nonatomic, readonly) double totalDistanceM;
/// Seconds since session start.
@property (nonatomic, readonly) double elapsedS;
/// Speed in km/h (uses GPS speed if available, else Kalman estimate).
@property (nonatomic, readonly) double speedKmh;
/// Rolling 30-second pace (min/km). 0 if not enough data.
@property (nonatomic, readonly) double paceMinPerKm;
/// Formatted pace string e.g. "5:23". "--:--" if unavailable.
@property (nonatomic, readonly) NSString *paceStr;
/// Whether this fix was accepted by the filter and used to update distance.
@property (nonatomic, readonly) BOOL accepted;
/// Whether the Live Activity should receive an update push this tick.
@property (nonatomic, readonly) BOOL shouldUpdateLiveActivity;

@end


/**
 * TrackEngineBridge — singleton wrapper around teng::SessionEngine.
 *
 * Thread safety: NOT thread-safe. Must be called from the same serial queue
 * as LocationEngine's delegate callbacks (which it already is).
 */
@interface TrackEngineBridge : NSObject

+ (instancetype)shared;

/**
 * Start a new tracking session.
 * Resets all accumulators, ring buffer, and Kalman state.
 *
 * @param unixTimeS    Unix time (seconds) at session start
 * @param laIntervalS  Minimum seconds between Live Activity updates (default 3.0)
 */
- (void)startSession:(double)unixTimeS liveActivityInterval:(double)laIntervalS;

/**
 * Stop the current session.
 */
- (void)stopSession;

/**
 * Ingest one GPS fix. Returns a TEFixResult describing the outcome.
 * Hot path — called on every CLLocation delegate tick.
 *
 * @param lat         Degrees WGS-84
 * @param lng         Degrees WGS-84
 * @param accuracy    Horizontal accuracy (metres). Pass negative to reject immediately.
 * @param unixTimeS   Unix timestamp (seconds)
 * @param speedMps    Speed in m/s from CLLocation. Pass negative if unavailable.
 */
- (TEFixResult *)ingestLat:(double)lat
                       lng:(double)lng
                  accuracy:(double)accuracy
               unixTimeS:(double)unixTimeS
                 speedMps:(double)speedMps;

/// Current total session distance in metres.
@property (nonatomic, readonly) double totalDistanceM;

/// Number of GPS points currently in the ring buffer.
@property (nonatomic, readonly) NSUInteger ringBufferCount;

/// Whether a session is active.
@property (nonatomic, readonly) BOOL isActive;

/// Configure the accuracy gate (default 50 m).
- (void)setMaxAccuracyM:(float)maxAccuracyM;

/// Configure the spike rejection speed (default 150 m/s).
- (void)setMaxSpeedMps:(float)maxSpeedMps;

@end

NS_ASSUME_NONNULL_END
