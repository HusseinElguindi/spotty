import Foundation
import XCTest
@testable import LauncherCore

final class SaveThrottleTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Replays changes and wake-ups, the way UsageFile drives it, and returns when writes happened.
    func writes(_ events: [(at: TimeInterval, change: SaveThrottle.Urgency?)], until end: TimeInterval) -> [TimeInterval] {
        var throttle = SaveThrottle()
        var wake: TimeInterval?
        var written: [TimeInterval] = []
        var queue = events.sorted { $0.at < $1.at }
        var clock: TimeInterval = 0
        while clock <= end {
            if let w = wake, w <= clock {
                wake = nil
                if throttle.fire(at: t0.addingTimeInterval(clock)) { written.append(clock) }
            }
            while let e = queue.first, e.at <= clock {
                queue.removeFirst()
                if let urgency = e.change, let due = throttle.changed(urgency, at: t0.addingTimeInterval(e.at)) {
                    wake = due.timeIntervalSince(t0)
                }
            }
            clock += 0.5
        }
        return written
    }

    func testManySwitchesGiveOneWrite() {
        // 40 switches over 50 seconds: one write, a minute after the first.
        let switches = (0..<40).map { (at: TimeInterval($0) * 1.25, change: SaveThrottle.Urgency?.some(.eventually)) }
        XCTAssertEqual(writes(switches, until: 200), [60])
    }

    func testSwitchesInLaterMinutesWriteAgain() {
        let switches = [0.0, 30, 59, 61, 100].map { (at: $0, change: SaveThrottle.Urgency?.some(.eventually)) }
        XCTAssertEqual(writes(switches, until: 300), [60, 121])
    }

    func testLaunchStillSavesQuickly() {
        XCTAssertEqual(writes([(at: 10, change: .soon)], until: 100), [12])
    }

    func testLaunchCarriesPendingSwitches() {
        // Switches pending, then a launch: one write two seconds after the launch, nothing at 60.
        let events: [(at: TimeInterval, change: SaveThrottle.Urgency?)] = [(0, .eventually), (5, .eventually), (10, .soon)]
        XCTAssertEqual(writes(events, until: 200), [12])
    }

    func testLaunchesDebounce() {
        let events: [(at: TimeInterval, change: SaveThrottle.Urgency?)] = [(0, .soon), (1, .soon), (2.5, .soon)]
        XCTAssertEqual(writes(events, until: 100), [4.5])
    }

    func testFlushWritesPendingChangesOnce() {
        var throttle = SaveThrottle()
        XCTAssertFalse(throttle.flush(), "nothing pending, nothing to write")
        _ = throttle.changed(.eventually, at: t0)
        XCTAssertTrue(throttle.flush())
        XCTAssertNil(throttle.due)
        XCTAssertFalse(throttle.fire(at: t0.addingTimeInterval(100)), "the flush already wrote it")
    }
}
