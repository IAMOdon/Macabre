//
//  ResultView.swift
//  Macabre

import SwiftUI

// MARK: - Apple Watch Ultra 3 (49mm) — 410 × 502 pt

struct ResultView: View {
    @EnvironmentObject var healthManager: RealHealthManager
    @State private var showingTimeBreakdown = false

    var formattedNumber: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: healthManager.remainingHeartbeats)) ?? "0"
    }

    var body: some View {
        ZStack {
            if showingTimeBreakdown {
                TimeBreakdownView(
                    healthManager: healthManager,
                    showTimeBreakdown: $showingTimeBreakdown
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                MainCountView(
                    formattedNumber: formattedNumber,
                    currentHeartRate: healthManager.currentHeartRate,
                    showTimeBreakdown: $showingTimeBreakdown
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showingTimeBreakdown)
    }
}

// MARK: - Main count (beats remaining)

struct MainCountView: View {
    let formattedNumber: String
    let currentHeartRate: Double
    @Binding var showTimeBreakdown: Bool
    @State private var breathe: CGFloat = 0

    private var accentColor: Color {
        if currentHeartRate < 60 { return .blue }
        else if currentHeartRate <= 100 { return .green }
        else { return .red }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle ambient glow
            RadialGradient(
                colors: [accentColor.opacity(0.15), .clear],
                center: .center,
                startRadius: 30,
                endRadius: 200
            )
            .ignoresSafeArea()
            .blur(radius: 40)

            VStack(spacing: 6) {
                Spacer()

                Text("Il te reste")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1.4)

                // Beat count — hero number
                Text(formattedNumber)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .shadow(color: accentColor.opacity(0.3), radius: 20)
                    .padding(.horizontal, 16)

                Text("battements de cœur")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer().frame(height: 12)

                // Frosted glass pill — tap hint
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Détails")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.06), lineWidth: 0.5)
                        )
                )

                Spacer()
            }
        }
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            showTimeBreakdown = true
        }
    }
}

// MARK: - Previews

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        ResultView().environmentObject(RealHealthManager.preview())
    }
}

struct MainCountView_Previews: PreviewProvider {
    static var previews: some View {
        MainCountView(
            formattedNumber: "2 133 935 993",
            currentHeartRate: 75,
            showTimeBreakdown: .constant(false)
        )
    }
}
