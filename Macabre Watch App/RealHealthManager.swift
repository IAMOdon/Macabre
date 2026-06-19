//
//  RealHealthManager.swift
//  Macabre Watch App
//
//  Owns the live heart-rate stream, the decrementing "beats remaining"
//  counter, and the offline catch-up that reconciles the count after the
//  app has been suspended. Heart-rate access is injected behind
//  `HeartRateProviding`, so the view model is fully testable without HealthKit.
//

import Foundation
import Combine
import WidgetKit
import os

// MARK: - View model

@MainActor
final class RealHealthManager: ObservableObject {
    @Published var currentHeartRate: Double = 0
    @Published var recentHeartRates: [Double] = []
    @Published var remainingHeartbeats: Int64 = 0

    private let provider: HeartRateProviding
    private let defaults: UserDefaults
    private let widgetDefaults: UserDefaults?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Macabre",
                                category: "health")

    private var birthDate: Date

    // Precision: accumulate fractional beats between 1-second ticks.
    private var beatRemainder: Double = 0

    // Save throttling: persist every N ticks rather than every second.
    private var ticksSinceLastSave = 0
    private let saveEveryNTicks = 30

    // Widget reload throttling (~5 min at one tick per second).
    private var ticksSinceLastWidgetReload = 0
    private let widgetReloadEveryNTicks = 300

    /// Snapshot of persisted beats/date captured at load — the single source
    /// of truth for catch-up, so we never re-read stale UserDefaults mid-flight.
    private var persistedBeatsSnapshot: Int64 = 0
    private var persistedDateSnapshot: Date = .distantPast

    /// Guards against overlapping catch-up runs (init + resume can race).
    private var catchUpInFlight = false

    private var tickTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?

    // Adaptive fallback: rolling average of real HR, used when no live HR is
    // available (watch off / charging). Falls back to the resting default.
    private var cachedAdaptiveBPM: Double?
    private var fallbackBPM: Double {
        if let cached = cachedAdaptiveBPM { return cached }
        let stored = defaults.double(forKey: MacabreConstants.DefaultsKey.sessionAverageBPM)
        let value = stored > 0 ? stored : MacabreConstants.restingHeartRate
        cachedAdaptiveBPM = value
        return value
    }

    init(provider: HeartRateProviding = HealthKitHeartRateProvider(),
         defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        self.widgetDefaults = UserDefaults(suiteName: MacabreConstants.appGroupSuiteName)
        self.birthDate = Self.loadBirthDate(from: defaults)
        loadState()
        startTicking()
        Task { await activateHealthKit() }
    }

    deinit {
        tickTask?.cancel()
        streamTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Persist state and refresh the widget when entering the background.
    func saveForBackground() {
        forceSave()
    }

    /// Catch up on beats missed while suspended when returning to the foreground.
    func resumeFromBackground() {
        let elapsed = Date().timeIntervalSince(persistedDateSnapshot)
        guard elapsed > 2 else { return }

        // Re-snapshot from whatever was last persisted (our own save, or the
        // widget's projected anchor) before reconciling.
        let freshBeats = defaults.int64(forKey: MacabreConstants.DefaultsKey.remainingHeartbeats)
            ?? remainingHeartbeats
        let freshDate = defaults.object(forKey: MacabreConstants.DefaultsKey.lastUpdatedDate) as? TimeInterval
            ?? persistedDateSnapshot.timeIntervalSince1970
        persistedBeatsSnapshot = freshBeats
        persistedDateSnapshot = Date(timeIntervalSince1970: freshDate)

        applySimpleCatchUp()                 // immediate visual estimate
        Task { await performCatchUp() }      // precise HealthKit reconciliation
    }

    // MARK: - HealthKit activation

    private func activateHealthKit() async {
        guard await provider.requestAuthorization() else {
            logger.notice("Heart-rate access unavailable; running on fallback estimate")
            return
        }
        await performCatchUp()
        startStreaming()
    }

    private func startStreaming() {
        streamTask?.cancel()
        let stream = provider.liveHeartRates()
        streamTask = Task { [weak self] in
            for await bpm in stream {
                self?.ingest(bpm)
            }
        }
    }

    private func ingest(_ heartRate: Double) {
        currentHeartRate = heartRate
        recentHeartRates.append(heartRate)
        if recentHeartRates.count > 60 {
            recentHeartRates.removeFirst()
        }
        updateAdaptiveAverage()
    }

    /// Recomputes the rolling average BPM and persists it as the fallback used
    /// when the watch reports no live heart rate.
    private func updateAdaptiveAverage() {
        guard recentHeartRates.count >= 3 else { return }
        let avg = recentHeartRates.reduce(0, +) / Double(recentHeartRates.count)
        guard avg > 30, avg < 220 else { return } // sanity bounds
        cachedAdaptiveBPM = avg
        defaults.set(avg, forKey: MacabreConstants.DefaultsKey.sessionAverageBPM)
        widgetDefaults?.set(avg, forKey: MacabreConstants.DefaultsKey.sessionAverageBPM)
    }

    // MARK: - Catch-up

    /// Quick `elapsed × BPM` estimate for immediate UI. Not persisted —
    /// `performCatchUp()` refines and saves the precise value.
    private func applySimpleCatchUp() {
        let elapsed = Date().timeIntervalSince(persistedDateSnapshot)
        guard elapsed > 0 else { return }
        let beatsElapsed = Int64(elapsed * fallbackBPM / 60.0)
        remainingHeartbeats = max(0, persistedBeatsSnapshot - beatsElapsed)
        beatRemainder = 0
    }

    /// Reconciles the count against the heart rate HealthKit actually recorded
    /// while we were suspended. Computes from the load-time snapshot and only
    /// ever moves the count down (monotonicity guard) so the user never sees
    /// the number tick upward.
    private func performCatchUp() async {
        guard !catchUpInFlight else { return }

        let snapshotDate = persistedDateSnapshot
        let snapshotBeats = persistedBeatsSnapshot
        let now = Date()
        let elapsed = now.timeIntervalSince(snapshotDate)
        guard elapsed > 2 else { return }

        catchUpInFlight = true
        defer { catchUpInFlight = false }

        let samples = await provider.samples(from: snapshotDate, to: now)
        let beats = CatchUp.beatsElapsed(since: snapshotDate, until: now,
                                         samples: samples, fallbackBPM: fallbackBPM)
        let computed = max(0, snapshotBeats - Int64(beats))

        remainingHeartbeats = min(remainingHeartbeats, computed)
        beatRemainder = 0
        forceSave()

        persistedBeatsSnapshot = remainingHeartbeats
        persistedDateSnapshot = now
        logger.debug("Catch-up: \(Int(beats)) beats over \(Int(elapsed))s from \(samples.count) samples")
    }

    // MARK: - Per-second decrement

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    /// Subtracts one second's worth of beats, accumulating the fraction for
    /// precision, and throttles disk writes and widget reloads.
    private func tick() {
        let effectiveBPM = currentHeartRate > 0 ? currentHeartRate : fallbackBPM
        beatRemainder += effectiveBPM / 60.0

        let wholeBeats = Int64(beatRemainder)
        if wholeBeats > 0 {
            beatRemainder -= Double(wholeBeats)
            remainingHeartbeats = max(0, remainingHeartbeats - wholeBeats)
        }

        ticksSinceLastSave += 1
        if ticksSinceLastSave >= saveEveryNTicks {
            saveState()
            ticksSinceLastSave = 0
        }

        ticksSinceLastWidgetReload += 1
        if ticksSinceLastWidgetReload >= widgetReloadEveryNTicks {
            ticksSinceLastWidgetReload = 0
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Persistence

    private func saveState() {
        let now = Date().timeIntervalSince1970
        for store in [defaults, widgetDefaults].compactMap({ $0 }) {
            store.set(remainingHeartbeats, forKey: MacabreConstants.DefaultsKey.remainingHeartbeats)
            store.set(now, forKey: MacabreConstants.DefaultsKey.lastUpdatedDate)
            if currentHeartRate > 0 {
                store.set(currentHeartRate, forKey: MacabreConstants.DefaultsKey.lastKnownHeartRate)
            }
        }
    }

    private func forceSave() {
        saveState()
        ticksSinceLastSave = 0
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Loads the persisted count without subtracting, capturing the snapshot
    /// for `performCatchUp()` and applying a quick visual estimate meanwhile.
    private func loadState() {
        guard
            let savedBeats = defaults.int64(forKey: MacabreConstants.DefaultsKey.remainingHeartbeats),
            let lastUpdated = defaults.object(forKey: MacabreConstants.DefaultsKey.lastUpdatedDate) as? TimeInterval
        else {
            calculateInitialRemainingHeartbeats()
            return
        }
        persistedBeatsSnapshot = savedBeats
        persistedDateSnapshot = Date(timeIntervalSince1970: lastUpdated)
        applySimpleCatchUp()
    }

    private func calculateInitialRemainingHeartbeats() {
        let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        let remainingYears = max(0, MacabreConstants.averageLifeExpectancy - age)
        remainingHeartbeats = Int64(remainingYears) * MacabreConstants.beatsPerYear
        persistedBeatsSnapshot = remainingHeartbeats
        persistedDateSnapshot = Date()
        forceSave()
    }

    /// The seed birth date. Until a birthday-input screen exists, this defaults
    /// to a neutral placeholder age (see `MacabreConstants.defaultAgeYears`);
    /// a persisted value, once present, always wins.
    private static func loadBirthDate(from defaults: UserDefaults) -> Date {
        if let saved = defaults.object(forKey: MacabreConstants.DefaultsKey.birthDate) as? TimeInterval {
            return Date(timeIntervalSince1970: saved)
        }
        return Calendar.current.date(byAdding: .year,
                                     value: -MacabreConstants.defaultAgeYears,
                                     to: Date()) ?? Date()
    }
}

#if DEBUG
extension RealHealthManager {
    /// A manager backed by a deterministic provider for SwiftUI previews —
    /// no HealthKit, no live timers hitting the canvas.
    static func preview(beats: Int64 = 2_080_879_386, bpm: Double = 75) -> RealHealthManager {
        let manager = RealHealthManager(provider: PreviewHeartRateProvider(),
                                        defaults: .standard)
        manager.remainingHeartbeats = beats
        manager.currentHeartRate = bpm
        return manager
    }
}

/// Emits nothing; used so previews don't touch HealthKit.
struct PreviewHeartRateProvider: HeartRateProviding {
    func requestAuthorization() async -> Bool { false }
    func samples(from start: Date, to end: Date) async -> [CatchUp.Sample] { [] }
    func liveHeartRates() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
}
#endif
