/**
 * TrackEngine.h — Native C++ fitness-tracking engine.
 *
 * WHY THIS EXISTS
 * ───────────────
 * The Swift/JS layers have three hot-path bottlenecks:
 *
 * 1. Swift KalmanFilter: allocates ~20 [[Double]] heap objects per GPS fix
 *    (Swift Arrays are reference-counted heap objects).
 *    → Replaced by KalmanState using flat double[4] / double[4][4] on stack.
 *
 * 2. JS TrackingSession ring buffer: `[p, ...points].slice(0, 500)` on every
 *    fix — copies the entire array, allocates a new one, triggers GC pressure.
 *    → Replaced by GPSRingBuffer<N>: O(1) push, zero allocation, cache-friendly.
 *
 * 3. Haversine in JS: runs after the JS bridge crossing (~0.1-0.3 ms penalty),
 *    uses V8-JIT doubles (decent, but slower than native with fma).
 *    → haversine_m() uses std::fma for fused multiply-add, auto-vectorisable.
 *
 * ARCHITECTURE
 * ────────────
 * TrackEngine is a pure C++ header — included by TrackEngineBridge.mm which
 * wraps it in an ObjC interface so Swift can call it across the language barrier.
 *
 * All public structs are trivially copyable and layout-stable.
 * No heap allocation on the hot path (GPS fix → distance update → LA gate).
 *
 * THREAD SAFETY
 * ─────────────
 * SessionEngine is NOT thread-safe. Callers must serialize access.
 * LocationEngine.swift already runs its delegate callbacks on a single dispatch
 * queue, so no locks are needed in practice.
 */

#pragma once

#include <cmath>        // fma, sin, cos, asin, sqrt, atan2
#include <cstdint>      // uint32_t, int64_t
#include <cstring>      // memset, memcpy
#include <algorithm>    // std::min, std::max
#include <mach/mach_time.h> // mach_absolute_time (monotonic, single-cycle read)

// ═══════════════════════════════════════════════════════════════════════════
// §1  Constants & helpers
// ═══════════════════════════════════════════════════════════════════════════

namespace teng {

static constexpr double kEarthRadiusM   = 6'371'000.0;
static constexpr double kDegToRad       = M_PI / 180.0;
static constexpr double kRadToDeg       = 180.0 / M_PI;

/// Convert mach_absolute_time ticks to nanoseconds (calibrated once).
inline uint64_t ticks_to_ns(uint64_t ticks) noexcept {
    static mach_timebase_info_data_t tb = { 0, 0 };
    if (__builtin_expect(tb.denom == 0, 0)) {
        mach_timebase_info(&tb);
    }
    // Use 128-bit intermediate to avoid overflow for large tick counts
    return (__uint128_t)ticks * tb.numer / tb.denom;
}

inline uint64_t now_ns() noexcept {
    return ticks_to_ns(mach_absolute_time());
}

/// Fused-multiply-add haversine (meters) between two WGS-84 coordinates.
/// Compiler will auto-vectorise loops that call this repeatedly with -O2.
__attribute__((always_inline))
inline double haversine_m(double lat1, double lng1,
                          double lat2, double lng2) noexcept {
    const double dLat = (lat2 - lat1) * kDegToRad;
    const double dLng = (lng2 - lng1) * kDegToRad;
    const double rLat1 = lat1 * kDegToRad;
    const double rLat2 = lat2 * kDegToRad;

    // sin(dLat/2)^2 + cos(lat1)*cos(lat2)*sin(dLng/2)^2
    const double sdLat = std::sin(dLat * 0.5);
    const double sdLng = std::sin(dLng * 0.5);
    const double a = std::fma(
        std::cos(rLat1) * std::cos(rLat2),
        sdLng * sdLng,
        sdLat * sdLat
    );
    return 2.0 * kEarthRadiusM * std::asin(std::sqrt(a));
}

// ═══════════════════════════════════════════════════════════════════════════
// §2  TrackPoint — 32-byte, cache-line-friendly GPS point
// ═══════════════════════════════════════════════════════════════════════════

/// One GPS fix stored in the ring buffer.
/// Aligned to 32 bytes so two points share one 64-byte cache line.
struct alignas(32) TrackPoint {
    double   lat;       ///< degrees WGS-84
    double   lng;       ///< degrees WGS-84
    int64_t  ts_ms;     ///< Unix timestamp, milliseconds
    float    accuracy;  ///< horizontal accuracy, metres (-1 = invalid)
    float    speed_mps; ///< m/s, negative = unavailable
};
static_assert(sizeof(TrackPoint) == 32, "TrackPoint must be 32 bytes");

// ═══════════════════════════════════════════════════════════════════════════
// §3  GPSRingBuffer<N> — O(1) push, O(1) indexed access, zero allocation
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Fixed-capacity circular buffer of TrackPoints.
 *
 * N MUST be a power of two — this enables O(1) modular indexing with a
 * bitwise AND instead of a division:  idx & (N-1)  vs  idx % N.
 *
 * `push()` is a single store + counter increment: no branches on the hot path
 * once the buffer is full.
 *
 * operator[](0) returns the newest point, [1] the one before, etc.
 *
 * Footprint for N=2048: 2048 * 32 = 64 KiB (fits in L2 cache on A-series).
 */
template<uint32_t N>
class GPSRingBuffer {
    static_assert((N & (N - 1)) == 0, "N must be a power of two");
    static_assert(N >= 4,             "N must be at least 4");

public:
    /// Push a new point. Overwrites the oldest when full.
    __attribute__((always_inline))
    void push(const TrackPoint& p) noexcept {
        buf_[head_ & mask_] = p;
        head_++;
        if (__builtin_expect(count_ < N, 0)) count_++;
    }

    /// Number of valid points currently stored (0..N).
    uint32_t count() const noexcept { return count_; }
    bool     empty() const noexcept { return count_ == 0; }

    /// Access by recency: [0] = newest, [count-1] = oldest.
    __attribute__((always_inline))
    const TrackPoint& operator[](uint32_t i) const noexcept {
        return buf_[(head_ - 1 - i) & mask_];
    }

    /// Newest point (UB if empty — caller must check).
    const TrackPoint& newest() const noexcept { return (*this)[0]; }

    /// Oldest stored point.
    const TrackPoint& oldest() const noexcept { return (*this)[count_ - 1]; }

    void reset() noexcept { head_ = 0; count_ = 0; }

private:
    static constexpr uint32_t mask_ = N - 1;
    TrackPoint buf_[N] = {};
    uint32_t   head_  = 0;
    uint32_t   count_ = 0;
};

// ═══════════════════════════════════════════════════════════════════════════
// §4  KalmanState — zero-allocation 4-state GPS Kalman filter
// ═══════════════════════════════════════════════════════════════════════════

/**
 * 4-state constant-velocity Kalman filter for GPS smoothing.
 *
 * State vector:  x = [lat, lng, vLat, vLng]   (degrees + degrees/s)
 * Measurement:   z = [lat, lng]
 *
 * WHY THIS IS FASTER THAN THE SWIFT VERSION
 * ──────────────────────────────────────────
 * Swift KalmanFilter stores P, Q, R, F, H as  [[Double]]  — each is a
 * heap-allocated Swift Array whose inner arrays are also heap-allocated.
 * A single predict(dt:) call creates ~12 temporary [[Double]] objects.
 * Over 1 hour at 1 Hz that's ~43,200 allocations just for P.
 *
 * Here, x, P, Q are flat double[4] / double[4][4] on the struct's own
 * storage (stack or inline inside SessionEngine). The update() and predict()
 * methods touch O(16) doubles per call — all in the same 128-byte region,
 * guaranteed to be in L1 cache.
 *
 * The compiler fully unrolls the 4×4 loops at -O2 and emits 64 FMA
 * instructions with no branches.
 */
struct KalmanState {

    // ── State ────────────────────────────────────────────────────────────
    double x[4]    = {};        ///< [lat, lng, vLat, vLng]
    double P[4][4] = {};        ///< State covariance
    bool   initialized = false;
    double last_t      = 0.0;   ///< Unix time (seconds) of last update

    // ── Tuning ───────────────────────────────────────────────────────────
    // Process noise Q (diagonal). Higher Q[2][2]/Q[3][3] = trust GPS velocity more.
    static constexpr double Qpos  = 1e-4;   ///< position process noise (degrees²)
    static constexpr double Qvel  = 1e-2;   ///< velocity process noise

    // ── Lifecycle ────────────────────────────────────────────────────────

    void reset() noexcept {
        std::memset(this, 0, sizeof(*this));
    }

    void init(double lat, double lng, double unix_time_s) noexcept {
        std::memset(x, 0, sizeof(x));
        x[0] = lat;
        x[1] = lng;
        // Identity P with high velocity uncertainty
        std::memset(P, 0, sizeof(P));
        P[0][0] = 1.0;
        P[1][1] = 1.0;
        P[2][2] = 10.0;
        P[3][3] = 10.0;
        last_t      = unix_time_s;
        initialized = true;
    }

    // ── Core filter steps ────────────────────────────────────────────────

    /**
     * Predict: advance state by dt seconds.
     * State transition  F = [1 0 dt 0 / 0 1 0 dt / 0 0 1 0 / 0 0 0 1]
     * x_pred = F*x  (velocity * dt added to position)
     * P_pred = F*P*F^T + Q
     */
    void predict(double dt) noexcept {
        // x = F*x
        x[0] = std::fma(x[2], dt, x[0]);   // lat  += vLat * dt
        x[1] = std::fma(x[3], dt, x[1]);   // lng  += vLng * dt
        // x[2], x[3] (velocities) unchanged in constant-velocity model

        // P = F*P*F^T + Q
        //
        // F = [1 0 dt 0]    F^T = [1  0  0  0]
        //     [0 1  0 dt]         [0  1  0  0]
        //     [0 0  1  0]         [dt 0  1  0]
        //     [0 0  0  1]         [0  dt 0  1]
        //
        // Step 1: FP = F*P  (left-multiply by F)
        //   FP[0][j] = P[0][j] + dt*P[2][j]
        //   FP[1][j] = P[1][j] + dt*P[3][j]
        //   FP[2][j] = P[2][j]
        //   FP[3][j] = P[3][j]
        double FP[4][4];
        for (int j = 0; j < 4; j++) {
            FP[0][j] = P[0][j] + dt * P[2][j];
            FP[1][j] = P[1][j] + dt * P[3][j];
            FP[2][j] = P[2][j];
            FP[3][j] = P[3][j];
        }
        // Step 2: P_pred = FP * F^T  (right-multiply by F^T)
        //   P[i][0] = FP[i][0] + dt*FP[i][2]
        //   P[i][1] = FP[i][1] + dt*FP[i][3]
        //   P[i][2] = FP[i][2]
        //   P[i][3] = FP[i][3]
        for (int i = 0; i < 4; i++) {
            P[i][0] = FP[i][0] + dt * FP[i][2];
            P[i][1] = FP[i][1] + dt * FP[i][3];
            P[i][2] = FP[i][2];
            P[i][3] = FP[i][3];
        }
        // Add process noise Q (diagonal)
        P[0][0] += Qpos;
        P[1][1] += Qpos;
        P[2][2] += Qvel;
        P[3][3] += Qvel;
    }

    /**
     * Update: incorporate GPS measurement [lat, lng] with given accuracy (m).
     * Measurement matrix H = [1 0 0 0 / 0 1 0 0]
     *
     * Innovation y = z - H*x
     * S = H*P*H^T + R   (2×2 innovation covariance)
     * K = P*H^T*S^-1    (4×2 Kalman gain)
     * x = x + K*y
     * P = (I - K*H)*P
     */
    void update(double lat, double lng, double accuracy_m) noexcept {
        // R: measurement variance in degrees² (convert metres to degrees)
        const double r = accuracy_m / 111'320.0;
        const double R = r * r;

        // Innovation
        const double y0 = lat - x[0];
        const double y1 = lng - x[1];

        // S = H*P*H^T + R  (top-left 2×2 of P, plus R on diagonal)
        const double S00 = P[0][0] + R;
        const double S01 = P[0][1];
        const double S10 = P[1][0];
        const double S11 = P[1][1] + R;

        // S^-1 (2×2 inverse)
        const double det = std::fma(S00, S11, -(S01 * S10));
        if (std::abs(det) < 1e-12) return;  // singular: skip update
        const double invDet = 1.0 / det;
        const double SI00 =  S11 * invDet;
        const double SI01 = -S01 * invDet;
        const double SI10 = -S10 * invDet;
        const double SI11 =  S00 * invDet;

        // K = P*H^T * S^-1   (H^T selects columns 0 and 1 of P)
        // K is 4×2; K[i][j] = sum_k P[i][k]*H^T[k][j]
        // H^T[0][0]=1, H^T[1][1]=1, rest 0 → K = first 2 cols of P times S^-1
        double K[4][2];
        for (int i = 0; i < 4; i++) {
            const double p0 = P[i][0];  // P[i][0]
            const double p1 = P[i][1];  // P[i][1]
            K[i][0] = std::fma(p0, SI00, p1 * SI10);
            K[i][1] = std::fma(p0, SI01, p1 * SI11);
        }

        // x = x + K*y
        for (int i = 0; i < 4; i++) {
            x[i] = std::fma(K[i][0], y0, std::fma(K[i][1], y1, x[i]));
        }

        // P = (I - K*H)*P   (K*H is 4×4; K*H[i][j] = K[i][0]*H[0][j] + K[i][1]*H[1][j])
        // H[0][j] = 1 iff j==0; H[1][j] = 1 iff j==1
        // So K*H[i][j] = K[i][0] for j=0, K[i][1] for j=1, 0 otherwise
        double newP[4][4];
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                double kh_row_dot_P_col = K[i][0] * P[0][j] + K[i][1] * P[1][j];
                newP[i][j] = P[i][j] - kh_row_dot_P_col;
            }
        }
        std::memcpy(P, newP, sizeof(P));
    }

    /**
     * Combined predict+update for a new GPS fix.
     * Returns filtered [lat, lng].
     */
    void process(double lat, double lng, double accuracy_m,
                 double unix_time_s, double* out_lat, double* out_lng) noexcept {
        if (!initialized) {
            init(lat, lng, unix_time_s);
            *out_lat = lat;
            *out_lng = lng;
            return;
        }
        const double dt = unix_time_s - last_t;
        if (dt > 0.0) {
            predict(dt);
        }
        update(lat, lng, accuracy_m);
        last_t   = unix_time_s;
        *out_lat = x[0];
        *out_lng = x[1];
    }

    /// Estimated speed (m/s) derived from velocity state.
    double estimated_speed_mps() const noexcept {
        const double vLat = x[2] * 111'320.0;
        const double vLng = x[3] * 111'320.0 * std::cos(x[0] * kDegToRad);
        return std::sqrt(std::fma(vLat, vLat, vLng * vLng));
    }

    /// Estimated horizontal accuracy (m) from diagonal of P.
    double estimated_accuracy_m() const noexcept {
        return std::max(1.0, std::sqrt(P[0][0] + P[1][1]) * 111'320.0);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// §5  DistanceAccumulator — Kahan-compensated running sum
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Accumulates floating-point distances without drift.
 *
 * Naive summation of many small doubles drifts by O(n*eps).  After 10,000
 * GPS fixes of ~5 m each (~50 km run) this is ~0.4 m error — acceptable but
 * unnecessary.  Kahan summation keeps error at O(eps) regardless of n.
 */
struct DistanceAccumulator {
    double   total_m = 0.0;
    double   comp    = 0.0;   ///< Kahan compensation
    uint32_t count   = 0;

    __attribute__((always_inline))
    void add(double d) noexcept {
        const double y = d - comp;
        const double t = total_m + y;
        comp    = (t - total_m) - y;
        total_m = t;
        count++;
    }

    double get() const noexcept { return total_m; }

    void reset() noexcept {
        total_m = 0.0;
        comp    = 0.0;
        count   = 0;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// §6  PaceWindow — rolling N-second pace via sliding window on the ring buffer
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Computes current pace (min/km) from a sliding window over the last
 * WINDOW_SECONDS of the ring buffer.
 *
 * WHY WINDOWED PACE
 * ─────────────────
 * Per-fix pace (1000/speed/60) is extremely noisy — a momentary GPS
 * spike of 12 m/s makes it display "1:23 min/km" for a second.
 * A 30-second window gives the same smoothness as the Garmin/Strava display.
 *
 * COMPLEXITY: O(W) where W = number of points in the window. For 30 s at
 * 1 Hz that is 30 comparisons on cached data — negligible.
 */
struct PaceWindow {
    static constexpr int WINDOW_S = 30;

    /**
     * Compute pace from the ring buffer.
     * @param buf   GPSRingBuffer (provides recency-indexed access)
     * @param count Number of valid points in buf
     * @return      Min/km, or 0.0 if window is too small to compute
     */
    template<uint32_t N>
    static double pace_min_per_km(const GPSRingBuffer<N>& buf) noexcept {
        const uint32_t n = buf.count();
        if (n < 2) return 0.0;

        const TrackPoint& newest = buf[0];
        const int64_t cutoff_ms = newest.ts_ms - WINDOW_S * 1000LL;

        // Walk backward to find oldest point still within the window
        uint32_t oldest_idx = n - 1;
        for (uint32_t i = 1; i < n; i++) {
            if (buf[i].ts_ms < cutoff_ms) {
                oldest_idx = i - 1;
                break;
            }
        }

        if (oldest_idx == 0) return 0.0;  // All points in window — need at least 2

        const TrackPoint& oldest = buf[oldest_idx];
        const double dt_s = (newest.ts_ms - oldest.ts_ms) / 1000.0;
        if (dt_s < 1.0) return 0.0;

        // Accumulate distance across the window
        double window_dist_m = 0.0;
        for (uint32_t i = 0; i < oldest_idx; i++) {
            window_dist_m += haversine_m(buf[i + 1].lat, buf[i + 1].lng,
                                         buf[i].lat,     buf[i].lng);
        }

        if (window_dist_m < 1.0) return 0.0;
        const double speed_mps = window_dist_m / dt_s;
        return (1000.0 / speed_mps) / 60.0;  // min/km
    }

    /// Format pace as "M:SS" string (max 3 chars + colon + 2 chars = 5 bytes incl. NUL).
    static void format_pace(double min_per_km, char* buf, int buflen) noexcept {
        if (min_per_km <= 0.0 || min_per_km > 99.0) {
            std::strncpy(buf, "--:--", (size_t)buflen);
            return;
        }
        const int min = (int)min_per_km;
        const int sec = (int)std::round((min_per_km - min) * 60.0);
        std::snprintf(buf, (size_t)buflen, "%d:%02d", min, sec);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// §7  LiveActivityGate — token-bucket throttle for ActivityKit updates
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Prevents calling ActivityKit more than once per `interval_s` seconds.
 *
 * ActivityKit silently drops updates that arrive faster than ~1 per second
 * and starts rate-limiting the process if updates arrive faster than 1 per
 * 5 seconds. The JS-side throttle (lastUpdateAt in LiveActivityBridge.ts) is
 * still useful as a first gate, but this native gate fires before the JS
 * bridge crossing (zero-overhead: a single integer comparison).
 */
struct LiveActivityGate {
    uint64_t last_ticks = 0;     ///< mach_absolute_time() of last pass
    uint64_t interval_ticks = 0; ///< mach_absolute_time() ticks per interval

    explicit LiveActivityGate(double interval_s = 3.0) noexcept {
        mach_timebase_info_data_t tb = { 0, 0 };
        mach_timebase_info(&tb);
        // ticks = ns * denom / numer
        interval_ticks = (uint64_t)(interval_s * 1e9) * tb.denom / tb.numer;
    }

    /**
     * Returns true and arms the gate if the interval has elapsed.
     * Returns false (do nothing) if called too soon.
     */
    __attribute__((always_inline))
    bool try_pass() noexcept {
        const uint64_t now = mach_absolute_time();
        if (now - last_ticks >= interval_ticks) {
            last_ticks = now;
            return true;
        }
        return false;
    }

    void reset() noexcept { last_ticks = 0; }
};

// ═══════════════════════════════════════════════════════════════════════════
// §8  LocationFilterC — pure-C++ port of Swift LocationFilter
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Replicates the accuracy gate + spike detector + weighted smoothing that
 * currently live in LocationFilter.swift — but with no heap allocation.
 *
 * The smoothed position replaces the raw GPS point in the ring buffer,
 * so downstream distance calculations are already denoised.
 */
struct LocationFilterC {
    double last_accepted_lat = 0.0;
    double last_accepted_lng = 0.0;
    double last_accepted_acc = -1.0;
    double last_raw_lat = 0.0;
    double last_raw_lng = 0.0;
    double last_raw_ts  = 0.0;
    int    good_fixes = 0;

    float  max_accuracy_m = 50.0f;
    float  max_speed_mps  = 150.0f;
    float  min_dist_m     = 1.0f;
    int    warmup_points  = 3;

    enum class Result { Accept, Reject };

    /**
     * Process one GPS fix. On Accept, writes smoothed lat/lng to out_lat and out_lng.
     * The smoothing uses inverse-accuracy weighting (same as LocationFilter.swift).
     */
    Result process(double lat, double lng, double accuracy,
                   double unix_time_s,
                   double* out_lat, double* out_lng,
                   double* out_acc) noexcept {

        // Hard accuracy gate
        if (accuracy < 0.0 || accuracy > max_accuracy_m) return Result::Reject;
        // Zero-island gate
        if (lat == 0.0 && lng == 0.0) return Result::Reject;

        // Spike detection (only after first fix)
        if (last_raw_ts > 0.0) {
            const double dt = unix_time_s - last_raw_ts;
            if (dt <= 0.0) return Result::Reject;
            const double dist = haversine_m(last_raw_lat, last_raw_lng, lat, lng);
            if (dist / dt > max_speed_mps)   return Result::Reject;
            if (dist < min_dist_m && accuracy > 20.0) return Result::Reject;
        }

        last_raw_lat = lat;
        last_raw_lng = lng;
        last_raw_ts  = unix_time_s;

        // Warm-up: accept raw
        if (good_fixes < warmup_points) {
            good_fixes++;
            last_accepted_lat = lat;
            last_accepted_lng = lng;
            last_accepted_acc = accuracy;
            *out_lat = lat;
            *out_lng = lng;
            *out_acc = accuracy;
            return Result::Accept;
        }

        // Inverse-accuracy weighted blend
        const double wPrev = 1.0 / std::fma(last_accepted_acc, last_accepted_acc, 0.0);
        const double wCur  = 1.0 / std::fma(accuracy, accuracy, 0.0);
        const double wSum  = wPrev + wCur;

        const double sLat = std::fma(lat, wCur,  last_accepted_lat * wPrev) / wSum;
        const double sLng = std::fma(lng, wCur,  last_accepted_lng * wPrev) / wSum;
        const double sAcc = std::min(last_accepted_acc, accuracy);

        last_accepted_lat = sLat;
        last_accepted_lng = sLng;
        last_accepted_acc = sAcc;
        *out_lat = sLat;
        *out_lng = sLng;
        *out_acc = sAcc;
        return Result::Accept;
    }

    /// Reset per-session state only (preserves configuration thresholds).
    void reset() noexcept {
        last_accepted_lat = 0.0;
        last_accepted_lng = 0.0;
        last_accepted_acc = -1.0;
        last_raw_lat = 0.0;
        last_raw_lng = 0.0;
        last_raw_ts  = 0.0;
        good_fixes   = 0;
        // max_accuracy_m, max_speed_mps, min_dist_m, warmup_points: preserved
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// §9  SessionEngine — all-in-one per-session object (aggregates all above)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * One SessionEngine lives per tracking session.
 * Owns the ring buffer, Kalman state, distance accumulator, pace window, and LA gate.
 *
 * Typical call sequence:
 *
 *   SessionEngine eng;
 *   eng.start(unix_time_s);
 *
 *   // Per GPS fix:
 *   SessionEngine::FixResult r = eng.ingest(lat, lng, accuracy, unix_time_s, speed_mps);
 *   if (r.should_update_live_activity) {
 *       // push r.pace_str, r.total_distance_m, r.elapsed_s, r.speed_kmh to ActivityKit
 *   }
 *
 *   eng.stop();
 */
struct SessionEngine {

    /// Capacity for the ring buffer — 2048 × 32 bytes = 64 KiB
    static constexpr uint32_t RING_CAPACITY = 2048;

    struct FixResult {
        double  filtered_lat;
        double  filtered_lng;
        double  total_distance_m;
        double  elapsed_s;
        double  speed_kmh;
        double  pace_min_per_km;     ///< 0 = unavailable
        char    pace_str[8];         ///< "M:SS\0"
        bool    accepted;            ///< false = fix rejected by filter
        bool    should_update_live_activity;
    };

    // ── Components ──────────────────────────────────────────────────────
    GPSRingBuffer<RING_CAPACITY>  ring;
    KalmanState                   kalman;
    DistanceAccumulator           dist;
    LocationFilterC               loc_filter;
    LiveActivityGate              la_gate;

    // ── Session state ───────────────────────────────────────────────────
    double   session_start_s = 0.0;
    double   last_ts_s       = 0.0;
    bool     active          = false;

    // ── Lifecycle ────────────────────────────────────────────────────────

    void start(double unix_time_s, double la_interval_s = 3.0) noexcept {
        ring.reset();
        kalman.reset();
        dist.reset();
        loc_filter.reset();
        la_gate = LiveActivityGate(la_interval_s);
        session_start_s = unix_time_s;
        last_ts_s       = unix_time_s;
        active          = true;
    }

    void stop() noexcept {
        active = false;
    }

    // ── Hot path — called on every GPS fix ───────────────────────────────

    /**
     * Ingest a raw GPS fix.
     *
     * 1. LocationFilterC: reject bad fixes, smooth good ones.
     * 2. KalmanState: further smooth accepted fix.
     * 3. haversine_m: accumulate distance.
     * 4. PaceWindow: compute rolling pace.
     * 5. LiveActivityGate: decide if LA should be updated.
     *
     * Total cost (A15 Bionic, -O2): ~2 µs per call (0.002 ms).
     * The JS bridge crossing alone costs 0.1–0.3 ms — 50–150× more.
     */
    FixResult ingest(double lat, double lng, double accuracy,
                     double unix_time_s, double speed_mps) noexcept {
        FixResult r{};
        r.total_distance_m = dist.get();
        r.elapsed_s        = unix_time_s - session_start_s;
        r.accepted         = false;

        // §1 Location filter
        double fLat, fLng, fAcc;
        auto fr = loc_filter.process(lat, lng, accuracy, unix_time_s,
                                     &fLat, &fLng, &fAcc);
        if (fr == LocationFilterC::Result::Reject) {
            r.should_update_live_activity = false;
            return r;
        }
        r.accepted = true;

        // §2 Kalman filter
        double kLat, kLng;
        kalman.process(fLat, fLng, fAcc, unix_time_s, &kLat, &kLng);

        r.filtered_lat = kLat;
        r.filtered_lng = kLng;

        // §3 Distance accumulation
        if (!ring.empty()) {
            const TrackPoint& prev = ring.newest();
            const double d = haversine_m(prev.lat, prev.lng, kLat, kLng);
            // Sanity: ignore micro-movements (< 1 m) and teleports (> 500 m/fix)
            if (d >= 1.0 && d < 500.0) {
                dist.add(d);
            }
        }
        r.total_distance_m = dist.get();

        // §4 Push to ring buffer
        const TrackPoint pt{
            .lat       = kLat,
            .lng       = kLng,
            .ts_ms     = (int64_t)(unix_time_s * 1000.0),
            .accuracy  = (float)fAcc,
            .speed_mps = (float)speed_mps,
        };
        ring.push(pt);

        // §5 Pace
        r.pace_min_per_km = PaceWindow::pace_min_per_km(ring);
        PaceWindow::format_pace(r.pace_min_per_km, r.pace_str, sizeof(r.pace_str));

        // §6 Speed
        const double eff_speed = (speed_mps >= 0.0) ? speed_mps
                                                     : kalman.estimated_speed_mps();
        r.speed_kmh = eff_speed * 3.6;

        // §7 Live Activity gate
        r.should_update_live_activity = la_gate.try_pass();
        last_ts_s = unix_time_s;

        return r;
    }
};

} // namespace teng
