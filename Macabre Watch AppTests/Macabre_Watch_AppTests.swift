//
//  Macabre_Watch_AppTests.swift
//  Macabre Watch AppTests
//
//  Unit tests for the pure logic shared by the app and the widget:
//  the heartbeats → time breakdown and the offline catch-up accounting.
//

import XCTest
@testable import Macabre_Watch_App

final class HeartbeatTimeTests: XCTestCase {

    func testZeroHeartbeatsIsAllZero() {
        let t = HeartbeatTime(heartbeats: 0)
        XCTAssertEqual(t.years, 0)
        XCTAssertEqual(t.days, 0)
        XCTAssertEqual(t.hours, 0)
        XCTAssertEqual(t.minutes, 0)
        XCTAssertEqual(t.seconds, 0)
    }

    func testTotalSecondsMatchesRate() {
        // 70 beats at 70 bpm == 60 s; 7 beats == 6 s. (Asserted on the
        // continuous value to avoid brittle integer-boundary rounding.)
        XCTAssertEqual(HeartbeatTime(heartbeats: 70).totalSeconds, 60, accuracy: 1e-6)
        XCTAssertEqual(HeartbeatTime(heartbeats: 7).totalSeconds, 6, accuracy: 1e-6)
    }

    func testComponentsRecombineToTotal() {
        // Re-expanding every component back into seconds should reconstruct the
        // continuous total (each truncation loses well under a second).
        let t = HeartbeatTime(heartbeats: 2_080_879_386)
        let recombined =
            Double(t.years) * 365.25 * 86_400
            + Double(t.days) * 86_400
            + Double(t.hours) * 3_600
            + Double(t.minutes) * 60
            + Double(t.seconds)
        XCTAssertEqual(recombined, t.totalSeconds, accuracy: 5)
    }

    func testBreakdownComponentsAreInRange() {
        let t = HeartbeatTime(heartbeats: 2_080_879_386)
        XCTAssertGreaterThan(t.years, 0)
        XCTAssertTrue((0..<366).contains(t.days))
        XCTAssertTrue((0..<24).contains(t.hours))
        XCTAssertTrue((0..<60).contains(t.minutes))
        XCTAssertTrue((0..<60).contains(t.seconds))
    }
}

final class CatchUpTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testNoSamplesUsesFallbackRate() {
        let beats = CatchUp.beatsElapsed(
            since: t0, until: t0.addingTimeInterval(60),
            samples: [], fallbackBPM: 60)
        XCTAssertEqual(beats, 60, accuracy: 0.0001) // 60 s at 1 beat/s
    }

    func testSingleSampleCoversWholeWindow() {
        let samples = [CatchUp.Sample(bpm: 120, start: t0)]
        let beats = CatchUp.beatsElapsed(
            since: t0, until: t0.addingTimeInterval(60),
            samples: samples, fallbackBPM: 60)
        XCTAssertEqual(beats, 120, accuracy: 0.0001) // 60 s at 2 beats/s
    }

    func testGapBeforeFirstSampleUsesFallback() {
        // 30 s unmeasured (fallback 60 bpm → 30 beats) + 30 s at 120 bpm (60 beats).
        let samples = [CatchUp.Sample(bpm: 120, start: t0.addingTimeInterval(30))]
        let beats = CatchUp.beatsElapsed(
            since: t0, until: t0.addingTimeInterval(60),
            samples: samples, fallbackBPM: 60)
        XCTAssertEqual(beats, 90, accuracy: 0.0001)
    }

    func testLongGapFallsBackAfterOneMinute() {
        // One sample at 120 bpm, then a 1-hour gap (watch off the wrist):
        // 60 s at the measured 2 beats/s = 120, the remaining 3540 s at the
        // fallback 1 beat/s = 3540 → 3660 total.
        let samples = [CatchUp.Sample(bpm: 120, start: t0)]
        let beats = CatchUp.beatsElapsed(
            since: t0, until: t0.addingTimeInterval(3600),
            samples: samples, fallbackBPM: 60)
        XCTAssertEqual(beats, 3660, accuracy: 0.0001)
    }
}

final class SeedBeatsTests: XCTestCase {

    func testSeedsFromAgeUsingAverageLifeExpectancy() {
        let birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date())!
        let beats = RealHealthManager.seedBeats(forBirthDate: birthDate)
        // 80 - 30 = 50 remaining years at the shared beats/year constant.
        XCTAssertEqual(beats, 50 * MacabreConstants.beatsPerYear)
    }

    func testClampsToZeroPastAverageLifeExpectancy() {
        let birthDate = Calendar.current.date(byAdding: .year, value: -90, to: Date())!
        XCTAssertEqual(RealHealthManager.seedBeats(forBirthDate: birthDate), 0)
    }
}

final class UserDefaultsInt64Tests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: "MacabreTests")
        defaults.removePersistentDomain(forName: "MacabreTests")
    }

    func testMissingKeyReturnsNil() {
        XCTAssertNil(defaults.int64(forKey: "absent"))
    }

    func testRoundTripsLargeInt64() {
        let value: Int64 = 2_080_879_386
        defaults.set(value, forKey: "beats")
        XCTAssertEqual(defaults.int64(forKey: "beats"), value)
    }
}
