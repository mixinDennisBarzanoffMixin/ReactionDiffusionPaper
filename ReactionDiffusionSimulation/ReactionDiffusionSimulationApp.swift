//
//  ReactionDiffusionSimulationApp.swift
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 15.11.23.
//

import SwiftUI

@main
struct ReactionDiffusionSimulationApp: App {
    @StateObject var generator = ImageGenerator()

    var body: some Scene {
        WindowGroup {
            ContentView(generator: generator)
                .environmentObject(generator)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
                case .background, .inactive:
                    generator.isRunning = false
                case .active:
                    generator.isRunning = true
                @unknown default:
                    break
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
}
