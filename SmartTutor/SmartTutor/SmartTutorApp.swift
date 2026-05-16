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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear { appDelegate.appState = appState }
        }
    }
}
