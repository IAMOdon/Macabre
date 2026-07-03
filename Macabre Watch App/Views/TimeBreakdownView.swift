//
// TimeBreakdownView.swift
// Macabre

import SwiftUI
import WatchKit

// MARK: - Apple Watch Ultra 3 (49mm) — 410 × 502 pt

struct TimeBreakdownView: View {
    @ObservedObject var healthManager: RealHealthManager
    @Binding var showTimeBreakdown: Bool

    private var tc: HeartbeatTime {
        HeartbeatTime(heartbeats: healthManager.remainingHeartbeats)
    }

    private var accentColor: Color {
        if healthManager.currentHeartRate < 60 { return .blue }
        else if healthManager.currentHeartRate <= 100 { return .green }
        else { return .red }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Ambient glow
            RadialGradient(
                colors: [accentColor.opacity(0.12), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .ignoresSafeArea()
            .blur(radius: 40)

            VStack(spacing: 14) {
                Spacer()

                // Row 1: years — days
                HStack(spacing: 10) {
                    GlassTimeUnit(value: tc.years, unit: "years", accent: accentColor)
                    GlassTimeUnit(value: tc.days, unit: "days", accent: accentColor)
                }

                // Row 2: hours — minutes
                HStack(spacing: 10) {
                    GlassTimeUnit(value: tc.hours, unit: "hours", accent: accentColor)
                    GlassTimeUnit(value: tc.minutes, unit: "min", accent: accentColor)
                }

                // Row 3: seconds (full width, smaller)
                GlassTimeUnit(value: tc.seconds, unit: "sec", accent: accentColor, compact: true)
                    .frame(maxWidth: 120)

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            showTimeBreakdown = false
        }
    }
}

// MARK: - Single frosted-glass time unit chip

private struct GlassTimeUnit: View {
    let value: Int
    let unit: LocalizedStringKey
    let accent: Color
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: compact ? 22 : 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(value)))

            Text(unit)
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(accent.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 8 : 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }
}

// MARK: - Previews

struct TimeBreakdownView_Previews: PreviewProvider {
    static var previews: some View {
        TimeBreakdownView(
            healthManager: .preview(beats: 2_000_000_000, bpm: 75),
            showTimeBreakdown: .constant(true)
        )
    }
}
