//
//  AppDelegate.swift
//  SmartTutor
//
//  Sprint 6 — APNs registration.
//
//  Responsibilities:
//    • Requests notification permission (alert + badge + sound) on first launch.
//    • Calls UIApplication.registerForRemoteNotifications() once permission granted.
//    • Receives the raw APNs device token and uploads it to the backend
//      via AppState.registerDeviceToken(_:).
//
//  Wired into SwiftUI via @UIApplicationDelegateAdaptor in SmartTutorApp.
//  AppState is injected via the weak `appState` property set in .onAppear.
//

import UIKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "AppDelegate")

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Injected from SmartTutorApp after the @StateObject initialises.
    weak var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error {
                logger.error("AppDelegate: push permission error — \(error.localizedDescription)")
            }
            guard granted else {
                logger.info("AppDelegate: user denied push notification permission")
                return
            }
            Task { @MainActor in
                logger.info("AppDelegate: permission granted — registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert raw bytes to lowercase hex string (64 chars for APNs tokens)
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.info("AppDelegate: APNs token received — \(tokenString.prefix(8))…")
        Task { @MainActor in
            await appState?.registerDeviceToken(tokenString)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Common in Simulator — not an error in development builds
        logger.warning("AppDelegate: APNs registration failed — \(error.localizedDescription)")
    }
}
