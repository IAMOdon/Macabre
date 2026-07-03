//
//  ContentView.swift
//  Macabre

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var healthManager: RealHealthManager
    @State private var currentPage: Int = 0

    var body: some View {
        if healthManager.needsBirthDate {
            BirthDateInputView()
                .environmentObject(healthManager)
        } else {
            TabView(selection: $currentPage) {
                ResultView()
                    .tag(0)

                BPMInsightsView(recentHeartRates: healthManager.recentHeartRates)
                    .tag(1)
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(healthManager)
        }
    }
}

// MARK: - Previews

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(RealHealthManager.preview())
    }
}
