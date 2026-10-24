//
//  ClockInterpolatorTests.swift
//  LineriOSUnitTests
//
//  Automated verification for CADisplayLink monotonic clock math and slewing.
//

import XCTest
@testable import LineriOS

@MainActor
final class ClockInterpolatorTests: XCTestCase {

    func testMonotonicAdvancementAtPlayingRate() {
        let clock = ClockInterpolator()
        let t0: CFTimeInterval = 1000.0
        let p0 = 30000 // 30 seconds

        clock.setAnchor(positionMs: p0, monotonicTime: t0, isPlaying: true)

        // Advance anchor by 250ms at rate R=1.0
        let t1 = t0 + 0.250
        clock.setAnchor(positionMs: p0 + 250, monotonicTime: t1, isPlaying: true)

        XCTAssertEqual(clock.interpolatedTimeMs, p0 + 250)
    }

    func testClockFreezesWhenPaused() {
        let clock = ClockInterpolator()
        let t0: CFTimeInterval = 1000.0
        let p0 = 45000 // 45 seconds

        clock.setAnchor(positionMs: p0, monotonicTime: t0, isPlaying: false)

        XCTAssertEqual(clock.interpolatedTimeMs, p0)

        // Advance monotonic time by 5 seconds while paused; position must remain p0
        clock.setAnchor(positionMs: p0, monotonicTime: t0 + 5.0, isPlaying: false)
        XCTAssertEqual(clock.interpolatedTimeMs, p0)
    }

    func testUserOffsetApplication() {
        let clock = ClockInterpolator()
        let t0: CFTimeInterval = 1000.0
        let p0 = 10000

        clock.setAnchor(positionMs: p0, monotonicTime: t0, isPlaying: false, userOffsetMs: 150)
        XCTAssertEqual(clock.interpolatedTimeMs, 10150)

        clock.setUserOffset(ms: -200)
        clock.setAnchor(positionMs: p0, monotonicTime: t0, isPlaying: false, userOffsetMs: -200)
        XCTAssertEqual(clock.interpolatedTimeMs, 9800)
    }
}
