//
//  SmartTutorApp.swift
//  SmartTutor
//

import SwiftUI

@main
struct SmartTutorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
