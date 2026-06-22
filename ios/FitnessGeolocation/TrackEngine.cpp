/**
 * TrackEngine.cpp — translation unit for the C++ tracking engine.
 *
 * All non-trivial implementation lives in TrackEngine.h (templated / inline).
 * This file exists purely so Xcode/CMake compile the header into a translation
 * unit and generate debug symbols for it.
 *
 * Unit Tests (compile-time assertions + runtime smoke tests)
 * ──────────────────────────────────────────────────────────
 * Enabled when TRACK_ENGINE_TESTS is defined.  Run via:
 *
 *   clang++ -std=c++17 -O2 -DTRACK_ENGINE_TESTS TrackEngine.cpp -o te_test && ./te_test
 */

#include "TrackEngine.h"

#ifdef TRACK_ENGINE_TESTS

#include <cstdio>
#include <cassert>
#include <cmath>

using namespace teng;

// ── Helpers ──────────────────────────────────────────────────────────────

static void pass(const char* name) { std::printf("  PASS  %s\n", name); }
static void fail(const char* name, const char* msg) {
    std::printf("  FAIL  %s  —  %s\n", name, msg);
    std::abort();
}
static bool near(double a, double b, double tol = 1e-3) {
    return std::abs(a - b) <= tol;
}

// ── Haversine ─────────────────────────────────────────────────────────────

static void test_haversine() {
    // London Waterloo to Covent Garden: ~1.33 km (verified)
    double d = haversine_m(51.5031, -0.1132, 51.5129, -0.1243);
    if (!near(d, 1333.0, 50.0)) fail("haversine_known", "distance out of range");

    // Same point → 0
    double z = haversine_m(51.5, -0.1, 51.5, -0.1);
    if (!near(z, 0.0, 1e-9)) fail("haversine_zero", "should be 0");

    // Antipodes: ~20015 km
    double a = haversine_m(0.0, 0.0, 0.0, 180.0);
    if (!near(a, 20'015'087.0, 1000.0)) fail("haversine_antipode", "antipode dist");

    pass("haversine");
}

// ── GPSRingBuffer ─────────────────────────────────────────────────────────

static void test_ring_buffer() {
    GPSRingBuffer<4> rb;  // Tiny capacity for easy overflow testing
    assert(rb.empty());
    assert(rb.count() == 0);

    TrackPoint p1 = { .lat=1, .lng=1, .ts_ms=1000 };
    TrackPoint p2 = { .lat=2, .lng=2, .ts_ms=2000 };
    TrackPoint p3 = { .lat=3, .lng=3, .ts_ms=3000 };
    TrackPoint p4 = { .lat=4, .lng=4, .ts_ms=4000 };
    TrackPoint p5 = { .lat=5, .lng=5, .ts_ms=5000 };

    rb.push(p1); assert(rb.count() == 1);
    rb.push(p2); assert(rb.count() == 2);
    rb.push(p3); assert(rb.count() == 3);
    rb.push(p4); assert(rb.count() == 4);

    // Newest is p4
    if (!near(rb[0].lat, 4.0)) fail("ring_newest", "newest should be p4");
    // Oldest is p1
    if (!near(rb[3].lat, 1.0)) fail("ring_oldest", "oldest should be p1");

    // Overflow: push p5, p1 is evicted
    rb.push(p5);
    assert(rb.count() == 4);  // capped at capacity
    if (!near(rb[0].lat, 5.0)) fail("ring_overflow_newest", "newest should be p5");
    if (!near(rb[3].lat, 2.0)) fail("ring_overflow_oldest", "oldest should be p2 after eviction");

    // reset
    rb.reset();
    assert(rb.empty());

    pass("GPSRingBuffer");
}

// ── KalmanState ──────────────────────────────────────────────────────────

static void test_kalman() {
    KalmanState k;

    // Repeated identical measurements should converge quickly
    const double lat0 = 51.5074, lng0 = -0.1278;
    double oLat = 0, oLng = 0;

    k.process(lat0, lng0, 5.0, 0.0, &oLat, &oLng);  // init
    // Add Gaussian noise ±0.0001° (~11 m)
    const double noise[] = { 0.0001, -0.0002, 0.00015, -0.00005, 0.0001,
                             -0.0001, 0.00008, -0.0003, 0.0002, -0.00012 };
    for (int i = 0; i < 10; i++) {
        k.process(lat0 + noise[i], lng0 + noise[i], 10.0,
                  (double)(i + 1), &oLat, &oLng);
    }

    // After 10 updates the filter should be within 20 m of truth
    // (noise ±0.0003° ≈ ±33 m; 10 iterations is not enough to beat that fully)
    double err = haversine_m(lat0, lng0, oLat, oLng);
    if (err > 20.0) {
        std::printf("    err=%.2f m\n", err);
        fail("kalman_converge", "filter did not converge within 20 m");
    }

    // reset
    k.reset();
    if (k.initialized) fail("kalman_reset", "should not be initialized after reset");

    pass("KalmanState");
}

// ── DistanceAccumulator ──────────────────────────────────────────────────

static void test_distance_accumulator() {
    DistanceAccumulator da;

    // 1000 additions of 50.0 should sum exactly to 50000.0 (Kahan)
    for (int i = 0; i < 1000; i++) da.add(50.0);
    if (!near(da.get(), 50000.0, 0.001)) fail("kahan_sum", "Kahan sum wrong");
    assert(da.count == 1000);

    da.reset();
    assert(near(da.get(), 0.0));

    pass("DistanceAccumulator");
}

// ── LiveActivityGate ────────────────────────────────────────────────────

static void test_la_gate() {
    LiveActivityGate gate(0.010);  // 10 ms interval for testing

    bool first = gate.try_pass();
    if (!first) fail("la_gate_first", "first call should always pass");

    bool second = gate.try_pass();
    if (second) fail("la_gate_throttle", "second immediate call should be blocked");

    // Sleep 15 ms
    struct timespec ts = { 0, 15'000'000 };
    nanosleep(&ts, nullptr);

    bool after_wait = gate.try_pass();
    if (!after_wait) fail("la_gate_after_wait", "call after interval should pass");

    pass("LiveActivityGate");
}

// ── SessionEngine end-to-end ─────────────────────────────────────────────

static void test_session_engine() {
    SessionEngine eng;
    eng.start(0.0, 0.0);  // zero LA interval = always fires

    // Simulate 10 GPS fixes 5 m apart along a straight line
    // ~0.000045 degrees per 5 m at equator
    const double step_deg = 5.0 / 111'320.0;
    double prev_dist = 0.0;

    for (int i = 0; i < 10; i++) {
        double lat = 51.5074 + i * step_deg;
        double lng = -0.1278;
        auto r = eng.ingest(lat, lng, 5.0, (double)i, 1.5);
        if (!r.accepted) fail("session_accept", "fix should be accepted");
        if (r.total_distance_m < prev_dist)
            fail("session_monotone", "distance should be monotonically increasing");
        prev_dist = r.total_distance_m;
    }

    // Total distance should be roughly 9 × ~5 m (Kalman smoothing shifts points slightly)
    double total = eng.dist.get();
    if (total < 30.0 || total > 60.0) {
        std::printf("    total_dist=%.2f\n", total);
        fail("session_distance", "total distance out of expected range [30, 60]");
    }

    // Pace string should be non-empty
    auto r = eng.ingest(51.5074 + 10 * step_deg, -0.1278, 5.0, 10.0, 1.5);
    if (r.pace_str[0] == '\0') fail("session_pace_str", "pace string should not be empty");

    eng.stop();
    pass("SessionEngine");
}

// ── Main ─────────────────────────────────────────────────────────────────

int main() {
    std::printf("TrackEngine tests\n");
    test_haversine();
    test_ring_buffer();
    test_kalman();
    test_distance_accumulator();
    test_la_gate();
    test_session_engine();
    std::printf("All tests passed.\n");
    return 0;
}

#endif // TRACK_ENGINE_TESTS
