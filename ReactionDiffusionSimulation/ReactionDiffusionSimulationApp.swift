//
//  ReactionDiffusionSimulationApp.swift
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 15.11.23.
//

import SwiftUI

class OnOffNotifier: ObservableObject {
    @Published var isRunning = true
}

@main
struct ReactionDiffusionSimulationApp: App {
    init() {
        self.onOffNotifier = OnOffNotifier()
    }
    

    @ObservedObject var onOffNotifier: OnOffNotifier
    
    var body: some Scene {
        WindowGroup {
            ContentView(onOffNotifier: onOffNotifier)
                .environmentObject(onOffNotifier)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
                case .background, .inactive:
                    onOffNotifier.isRunning = false
                case .active:
                    onOffNotifier.isRunning = true
                @unknown default:
                    break
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
}
