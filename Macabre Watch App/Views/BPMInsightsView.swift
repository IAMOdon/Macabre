//
//  BPMInsightsView.swift
//  Macabre

import SwiftUI

// MARK: - Apple Watch Ultra 3 (49mm) — 410 × 502 pt
// Fixed layout (no ScrollView) — everything fits the full screen.

struct BPMInsightsView: View {
    let recentHeartRates: [Double]
    @State private var dotPulse = false

    private var currentBPM: Int { Int(recentHeartRates.last ?? 0) }
    private var avgBPM: Int {
        guard !recentHeartRates.isEmpty else { return 0 }
        return Int(recentHeartRates.reduce(0, +) / Double(recentHeartRates.count))
    }
    private var minBPM: Int { Int(recentHeartRates.min() ?? 0) }
    private var maxBPM: Int { Int(recentHeartRates.max() ?? 0) }

    private var lineColor: Color {
        let bpm = Double(currentBPM)
        if bpm < 60 { return .blue }
        else if bpm <= 100 { return .green }
        else { return .red }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Ambient glow
            RadialGradient(
                colors: [lineColor.opacity(0.1), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 250
            )
            .ignoresSafeArea()
            .blur(radius: 40)

            VStack(spacing: 8) {
                // Header
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(lineColor)
                    Text("Insights")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    // Live BPM badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(lineColor)
                            .frame(width: 6, height: 6)
                            .scaleEffect(dotPulse ? 1.3 : 1.0)
                        Text("\(currentBPM)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                // Chart card — takes available space
                GeometryReader { geo in
                    ZStack {
                        if recentHeartRates.count >= 2 {
                            // Area fill
                            HeartRateAreaShape(data: recentHeartRates)
                                .fill(
                                    LinearGradient(
                                        colors: [lineColor.opacity(0.2), lineColor.opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            // Line
                            HeartRateLineShape(data: recentHeartRates)
                                .stroke(
                                    LinearGradient(
                                        colors: [lineColor.opacity(0.5), lineColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                )

                            // Dot
                            if let last = recentHeartRates.last {
                                let cnt = max(CGFloat(recentHeartRates.count - 1), 1)
                                let lo = recentHeartRates.min() ?? 60
                                let hi = recentHeartRates.max() ?? 100
                                let rng = max(hi - lo, 1)
                                let x = CGFloat(recentHeartRates.count - 1) / cnt * geo.size.width
                                let y = (1 - CGFloat((last - lo) / rng)) * geo.size.height

                                Circle()
                                    .fill(lineColor)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: lineColor.opacity(0.6), radius: 5)
                                    .position(x: x, y: y)
                                    .scaleEffect(dotPulse ? 1.4 : 1.0)
                                    .opacity(dotPulse ? 0.6 : 1.0)
                            }
                        } else {
                            Text("En attente de données…")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 12)

                // Stats row — 3 compact glass pills
                HStack(spacing: 5) {
                    StatPill(label: "moy", value: "\(avgBPM)", color: lineColor)
                    StatPill(label: "min", value: "\(minBPM)", color: .blue)
                    StatPill(label: "max", value: "\(maxBPM)", color: .red)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
        }
    }
}

// MARK: - Stat pill

private struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(color.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Line shape (normalised to min/max)

private struct HeartRateLineShape: Shape {
    let data: [Double]

    func path(in rect: CGRect) -> Path {
        guard data.count >= 2 else { return Path() }
        let minVal = data.min()!
        let maxVal = data.max()!
        let range = max(maxVal - minVal, 1)
        let count = CGFloat(data.count - 1)

        var p = Path()
        for (i, v) in data.enumerated() {
            let x = CGFloat(i) / count * rect.width
            let y = (1 - CGFloat((v - minVal) / range)) * rect.height
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

// MARK: - Area fill shape

private struct HeartRateAreaShape: Shape {
    let data: [Double]

    func path(in rect: CGRect) -> Path {
        guard data.count >= 2 else { return Path() }
        let minVal = data.min()!
        let maxVal = data.max()!
        let range = max(maxVal - minVal, 1)
        let count = CGFloat(data.count - 1)

        var p = Path()
        for (i, v) in data.enumerated() {
            let x = CGFloat(i) / count * rect.width
            let y = (1 - CGFloat((v - minVal) / range)) * rect.height
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Previews

struct BPMInsightsView_Previews: PreviewProvider {
    static var previews: some View {
        BPMInsightsView(recentHeartRates: [65, 70, 75, 80, 72, 68, 76, 82, 71, 77])
    }
}

//  Created by Armand S Wegnez on 11/23/24.
