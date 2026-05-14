//
//  SmartTutorApp.swift
//  SmartTutor
//

import SwiftUI
import UserNotifications

@main
struct SmartTutorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear { appDelegate.appState = appState }
        }
    }
}
