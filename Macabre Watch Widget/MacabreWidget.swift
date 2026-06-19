//
//  MacabreWidget.swift
//  Macabre Watch Widget
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct MacabreEntry: TimelineEntry {
    let date: Date
    let remainingHeartbeats: Int64
    let lastKnownBPM: Double

    var timeLeft: HeartbeatTime { HeartbeatTime(heartbeats: remainingHeartbeats) }

    var formattedBeats: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: remainingHeartbeats)) ?? "0"
    }

    var compactBeats: String {
        let b = remainingHeartbeats
        if b >= 1_000_000_000 { return String(format: "%.1fBt", Double(b) / 1_000_000_000) }
        if b >= 1_000_000     { return String(format: "%.1fMt", Double(b) / 1_000_000) }
        return String(format: "%.0fKt", Double(b) / 1_000)
    }
}

// MARK: - Timeline Provider

struct MacabreTimelineProvider: TimelineProvider {
    private let provider: HeartRateProviding = HealthKitHeartRateProvider()

    private var defaults: UserDefaults {
        UserDefaults(suiteName: MacabreConstants.appGroupSuiteName) ?? .standard
    }

    /// Adaptive average BPM persisted by the main app, or the resting default.
    private var adaptiveFallbackBPM: Double {
        let avg = defaults.double(forKey: MacabreConstants.DefaultsKey.sessionAverageBPM)
        return avg > 0 ? avg : MacabreConstants.restingHeartRate
    }

    func placeholder(in context: Context) -> MacabreEntry {
        MacabreEntry(date: Date(), remainingHeartbeats: 2_000_000_000, lastKnownBPM: 70)
    }

    func getSnapshot(in context: Context, completion: @escaping (MacabreEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacabreEntry>) -> Void) {
        Task {
            let (correctedBeats, latestBPM) = await fetchCorrectedBaseline()
            let bps = latestBPM / 60.0
            let now = Date()

            let entries: [MacabreEntry] = (0..<120).map { offset in
                let beatsElapsed = Int64(Double(offset * 60) * bps)
                return MacabreEntry(
                    date: now.addingTimeInterval(Double(offset) * 60),
                    remainingHeartbeats: max(0, correctedBeats - beatsElapsed),
                    lastKnownBPM: latestBPM
                )
            }

            let refreshDate = now.addingTimeInterval(60 * 60)
            completion(Timeline(entries: entries, policy: .after(refreshDate)))
        }
    }

    /// Queries HealthKit for samples since the last saved snapshot, computes the
    /// accurate beat count (the shared `CatchUp` algorithm the app also uses),
    /// and persists the corrected baseline so the app's catch-up window stays small.
    private func fetchCorrectedBaseline() async -> (beats: Int64, bpm: Double) {
        let defaults = self.defaults
        let savedBeats = defaults.int64(forKey: MacabreConstants.DefaultsKey.remainingHeartbeats) ?? 0
        let lastUpdated = defaults.object(forKey: MacabreConstants.DefaultsKey.lastUpdatedDate) as? TimeInterval
            ?? Date().timeIntervalSince1970
        let cachedBPM = defaults.double(forKey: MacabreConstants.DefaultsKey.lastKnownHeartRate)
        let fallbackBPM = cachedBPM > 0 ? cachedBPM : adaptiveFallbackBPM
        let snapshotDate = Date(timeIntervalSince1970: lastUpdated)
        let now = Date()

        let samples = await provider.samples(from: snapshotDate, to: now)
        let beats = CatchUp.beatsElapsed(since: snapshotDate, until: now,
                                         samples: samples, fallbackBPM: fallbackBPM)
        let latestBPM = samples.last?.bpm ?? fallbackBPM
        let corrected = max(0, savedBeats - Int64(beats))

        defaults.set(corrected, forKey: MacabreConstants.DefaultsKey.remainingHeartbeats)
        defaults.set(now.timeIntervalSince1970, forKey: MacabreConstants.DefaultsKey.lastUpdatedDate)
        defaults.set(latestBPM, forKey: MacabreConstants.DefaultsKey.lastKnownHeartRate)
        return (corrected, latestBPM)
    }

    /// A best-effort entry projected from the last saved anchor, rewritten as a
    /// fresh anchor so the app's catch-up window is at most one refresh interval.
    private func currentEntry() -> MacabreEntry {
        let defaults = self.defaults
        let savedBeats = defaults.int64(forKey: MacabreConstants.DefaultsKey.remainingHeartbeats) ?? 0
        let lastUpdated = defaults.object(forKey: MacabreConstants.DefaultsKey.lastUpdatedDate) as? TimeInterval
            ?? Date().timeIntervalSince1970
        let savedBPM = defaults.double(forKey: MacabreConstants.DefaultsKey.lastKnownHeartRate)
        let bpm = savedBPM > 0 ? savedBPM : adaptiveFallbackBPM

        let now = Date()
        let elapsed = now.timeIntervalSince1970 - lastUpdated
        let beatsElapsed = Int64(elapsed * (bpm / 60.0))
        let current = max(0, savedBeats - beatsElapsed)

        defaults.set(current, forKey: MacabreConstants.DefaultsKey.remainingHeartbeats)
        defaults.set(now.timeIntervalSince1970, forKey: MacabreConstants.DefaultsKey.lastUpdatedDate)

        return MacabreEntry(date: now, remainingHeartbeats: current, lastKnownBPM: bpm)
    }
}

// MARK: - Rectangular complication (large, primary)

struct MacabreRectangularView: View {
    let entry: MacabreEntry
    @Environment(\.isLuminanceReduced) var dim

    var body: some View {
        let t = entry.timeLeft
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(dim ? .gray : .red)
                    .symbolEffect(.pulse, options: .repeating, isActive: !dim)

                Text(entry.formattedBeats)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(dim ? .gray : .white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            HStack(spacing: 3) {
                timeChip("\(t.years)",   "a")
                timeChip("\(t.days)",    "j")
                timeChip("\(t.hours)",   "h")
                timeChip("\(t.minutes)", "m")
            }
        }
        .opacity(dim ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func timeChip(_ value: String, _ unit: String) -> some View {
        HStack(spacing: 1) {
            Text(value)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(dim ? .gray : .white)
            Text(unit)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(dim ? .gray.opacity(0.7) : .white.opacity(0.6))
        }
    }
}

// MARK: - Inline complication

struct MacabreInlineView: View {
    let entry: MacabreEntry

    var body: some View {
        let t = entry.timeLeft
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
            Text("\(entry.compactBeats) · \(t.years)a \(t.days)j")
        }
    }
}

// MARK: - Corner complication

struct MacabreCornerView: View {
    let entry: MacabreEntry
    @Environment(\.isLuminanceReduced) var dim

    var body: some View {
        let t = entry.timeLeft
        Text(entry.compactBeats)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(dim ? .gray : .white)
            .widgetLabel {
                Text("\(t.years)a \(t.days)j \(t.hours)h")
            }
    }
}

// MARK: - Widget entry view dispatcher

struct MacabreWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MacabreEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: MacabreRectangularView(entry: entry)
        case .accessoryInline:      MacabreInlineView(entry: entry)
        case .accessoryCorner:      MacabreCornerView(entry: entry)
        default:                    MacabreRectangularView(entry: entry)
        }
    }
}

// MARK: - Widget configuration

@main
struct MacabreWidget: Widget {
    let kind: String = "MacabreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacabreTimelineProvider()) { entry in
            MacabreWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Macabre")
        .description("Battements de cœur et temps restants")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Previews

#Preview("Rectangular", as: .accessoryRectangular) {
    MacabreWidget()
} timeline: {
    MacabreEntry(date: .now, remainingHeartbeats: 1_840_000_000, lastKnownBPM: 70)
}

#Preview("Inline", as: .accessoryInline) {
    MacabreWidget()
} timeline: {
    MacabreEntry(date: .now, remainingHeartbeats: 1_840_000_000, lastKnownBPM: 70)
}

#Preview("Corner", as: .accessoryCorner) {
    MacabreWidget()
} timeline: {
    MacabreEntry(date: .now, remainingHeartbeats: 1_840_000_000, lastKnownBPM: 70)
}
