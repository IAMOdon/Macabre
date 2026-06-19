//
//  HeartbeatMath.swift
//  Macabre — shared between the watch app and the widget extension.
//
//  Single source of truth for the pure, deterministic logic that both
//  targets need: tuning constants, app-group keys, the heartbeats → time
//  breakdown, and the offline catch-up accounting. Keeping it here means
//  the app and the complication can never drift out of sync, and the math
//  is unit-testable without HealthKit or a UI.
//

import Foundation
import HealthKit

// MARK: - Constants

/// App-wide tuning values and persistence keys shared by both targets.
///
/// > Note: `appGroupSuiteName` must match the App Group configured in both
/// > targets' entitlements. See the README for the one place you change it
/// > when building under your own team.
enum MacabreConstants {
    /// Shared App Group used to hand data to the widget. Change this to your
    /// own group identifier (and update both `.entitlements` files) to build.
    static let appGroupSuiteName = "group.armandwegnez.Macabre"

    /// Average life expectancy, in years, used to seed the initial count.
    static let averageLifeExpectancy = 80

    /// Placeholder age used to seed the count until a birthday-input screen
    /// lets the user supply their own date of birth.
    static let defaultAgeYears = 30

    /// Resting heart rate assumed when converting a beat count into a time
    /// span, and used as the static fallback when no live HR is available.
    static let restingHeartRate: Double = 70

    /// 70 BPM × 525 600 minutes per year.
    static let beatsPerYear: Int64 = 36_792_000

    /// UserDefaults keys, shared so the app and widget read/write the same data.
    enum DefaultsKey {
        static let remainingHeartbeats = "RemainingHeartbeats"
        static let lastUpdatedDate = "LastUpdatedDate"
        static let birthDate = "BirthDate"
        static let lastKnownHeartRate = "LastKnownHeartRate"
        static let sessionAverageBPM = "SessionAverageBPM"
    }
}

// MARK: - Heartbeats → time breakdown

/// Converts a remaining-heartbeat count into a human-readable time breakdown,
/// assuming an average resting heart rate. Pure and deterministic.
struct HeartbeatTime: Equatable, Sendable {
    let heartbeats: Int64
    var beatsPerMinute: Double = MacabreConstants.restingHeartRate

    private static let secondsPerMinute: Double = 60
    private static let minutesPerHour: Double = 60
    private static let hoursPerDay: Double = 24
    private static let daysPerYear: Double = 365.25

    var totalSeconds: Double {
        Double(heartbeats) / (beatsPerMinute / Self.secondsPerMinute)
    }
    var totalMinutes: Double { totalSeconds / Self.secondsPerMinute }

    var years: Int {
        Int(totalMinutes / (Self.minutesPerHour * Self.hoursPerDay * Self.daysPerYear))
    }
    var days: Int {
        let rem = totalMinutes.truncatingRemainder(
            dividingBy: Self.minutesPerHour * Self.hoursPerDay * Self.daysPerYear)
        return Int(rem / (Self.minutesPerHour * Self.hoursPerDay))
    }
    var hours: Int {
        let rem = totalMinutes.truncatingRemainder(dividingBy: Self.minutesPerHour * Self.hoursPerDay)
        return Int(rem / Self.minutesPerHour)
    }
    var minutes: Int { Int(totalMinutes.truncatingRemainder(dividingBy: Self.minutesPerHour)) }
    var seconds: Int { Int(totalSeconds.truncatingRemainder(dividingBy: Self.secondsPerMinute)) }
}

// MARK: - Offline catch-up accounting

/// Computes how many heartbeats elapsed while the app/widget was inactive.
///
/// The algorithm walks the heart-rate samples HealthKit recorded during the
/// offline window: each gap between consecutive samples is counted at that
/// sample's rate, while long gaps (the watch was off the wrist) fall back to
/// an estimated rate. Decoupled from HealthKit so it can be unit-tested.
enum CatchUp {
    /// A single heart-rate reading at a point in time.
    struct Sample: Equatable, Sendable {
        let bpm: Double
        let start: Date
    }

    /// Gaps longer than this (in seconds) are treated as "watch was off":
    /// the measured rate is applied only briefly, then the fallback takes over.
    static let watchOffThreshold: TimeInterval = 1800

    /// Total beats between `snapshotDate` and `now`, given the recorded
    /// `samples` (ascending by start) and a `fallbackBPM` for unmeasured gaps.
    static func beatsElapsed(
        since snapshotDate: Date,
        until now: Date,
        samples: [Sample],
        fallbackBPM: Double
    ) -> Double {
        let fallbackBPS = fallbackBPM / 60.0
        guard !samples.isEmpty else {
            return max(0, now.timeIntervalSince(snapshotDate)) * fallbackBPS
        }

        var total: Double = 0

        // Gap before the first sample is unmeasured → fallback rate.
        if samples[0].start > snapshotDate {
            total += samples[0].start.timeIntervalSince(snapshotDate) * fallbackBPS
        }

        for i in samples.indices {
            let bps = samples[i].bpm / 60.0
            let start = samples[i].start
            let end = (i + 1 < samples.count) ? samples[i + 1].start : now
            let gap = max(0, end.timeIntervalSince(start))

            if gap > watchOffThreshold {
                // Watch likely off the wrist: count the measured rate briefly,
                // then fall back for the remainder.
                total += min(gap, 60) * bps
                total += max(0, gap - 60) * fallbackBPS
            } else {
                total += gap * bps
            }
        }
        return total
    }
}

// MARK: - Typed UserDefaults access

extension UserDefaults {
    /// Reads an `Int64`, tolerating the `Int`/`NSNumber` bridging that
    /// `UserDefaults` may apply. Returns `nil` when the key is absent.
    func int64(forKey key: String) -> Int64? {
        guard let raw = object(forKey: key) else { return nil }
        if let v = raw as? Int64 { return v }
        if let v = raw as? Int { return Int64(v) }
        if let n = raw as? NSNumber { return n.int64Value }
        return nil
    }
}

// MARK: - Heart-rate dependency (injection seam)

/// Abstraction over the heart-rate source, shared by the app and the widget.
/// The production type wraps HealthKit; tests and previews inject a
/// deterministic stand-in.
protocol HeartRateProviding: Sendable {
    /// Requests read access. Returns `false` if HealthKit is unavailable
    /// or the request errored.
    func requestAuthorization() async -> Bool

    /// All heart-rate samples in `[start, end]`, ascending by start date.
    func samples(from start: Date, to end: Date) async -> [CatchUp.Sample]

    /// A stream of live heart-rate values as HealthKit records them.
    func liveHeartRates() -> AsyncStream<Double>
}

/// Production `HeartRateProviding` backed by HealthKit.
///
/// `HKHealthStore` is documented as thread-safe and every stored property is
/// immutable, so the type is safe to share across concurrency domains.
final class HealthKitHeartRateProvider: HeartRateProviding, @unchecked Sendable {
    private let store = HKHealthStore()
    private let heartRateType = HKQuantityType(.heartRate)
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [heartRateType])
            try? await store.enableBackgroundDelivery(for: heartRateType, frequency: .immediate)
            return true
        } catch {
            return false
        }
    }

    func samples(from start: Date, to end: Date) async -> [CatchUp.Sample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let unit = bpmUnit
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, _ in
                let mapped = (samples as? [HKQuantitySample] ?? []).map {
                    CatchUp.Sample(bpm: $0.quantity.doubleValue(for: unit), start: $0.startDate)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func liveHeartRates() -> AsyncStream<Double> {
        let store = store
        let type = heartRateType
        let unit = bpmUnit
        return AsyncStream { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-300), end: nil, options: .strictEndDate)
            let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { _, samples, _, _, _ in
                for sample in (samples as? [HKQuantitySample] ?? []) {
                    continuation.yield(sample.quantity.doubleValue(for: unit))
                }
            }
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil,
                                              limit: HKObjectQueryNoLimit, resultsHandler: handler)
            query.updateHandler = handler
            continuation.onTermination = { _ in store.stop(query) }
            store.execute(query)
        }
    }
}
