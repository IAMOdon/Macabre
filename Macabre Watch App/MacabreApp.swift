//
//  MacabreApp.swift
//  Macabre Watch App
//
//  Created by Armand S Wegnez on 9/21/24.
//

import SwiftUI

@main
struct HeartbeatApp: App {
    @StateObject private var healthManager = RealHealthManager()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                healthManager.saveForBackground()
            case .active:
                healthManager.resumeFromBackground()
            @unknown default:
                break
            }
        }
    }
}
