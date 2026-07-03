//
//  BirthDateInputView.swift
//  Macabre
//
//  One-time onboarding screen: replaces the placeholder-age seed with the
//  user's real date of birth. Shown instead of ContentView's TabView while
//  `RealHealthManager.needsBirthDate` is true.
//

import SwiftUI
import WatchKit

struct BirthDateInputView: View {
    @EnvironmentObject var healthManager: RealHealthManager

    @State private var selectedDate = Calendar.current.date(
        byAdding: .year, value: -MacabreConstants.defaultAgeYears, to: Date()) ?? Date()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.08), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .ignoresSafeArea()
            .blur(radius: 40)

            VStack(spacing: 10) {
                Text("When were you born?")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Text("For a countdown that's truly yours")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                DatePicker(
                    "Date of birth",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()

                Button {
                    WKInterfaceDevice.current().play(.click)
                    healthManager.setBirthDate(selectedDate)
                } label: {
                    Text("Confirm")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Previews

struct BirthDateInputView_Previews: PreviewProvider {
    static var previews: some View {
        BirthDateInputView()
            .environmentObject(RealHealthManager.preview())
    }
}
