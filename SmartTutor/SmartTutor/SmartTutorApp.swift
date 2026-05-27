//
//  SmartTutorApp.swift
//  SmartTutor
//

import SwiftUI
import UserNotifications

@main
struct SmartTutorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appearanceManager.appearanceMode.colorScheme)
                .onAppear {
                    appDelegate.appState = appState
                    appearanceManager.applyAppearance()
                }
        }
    }
}
