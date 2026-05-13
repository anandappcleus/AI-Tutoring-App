//
//  SmartTutorApp.swift
//  SmartTutor
//

import SwiftUI

@main
struct SmartTutorApp: App {
    @StateObject private var appState    = AppState()
    @StateObject private var syncManager = OfflineSyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(syncManager)
        }
    }
}
