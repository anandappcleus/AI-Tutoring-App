//
//  AppLogger.swift
//  SmartTutor
//
//  Centralized structured logging for SmartTutor.
//  Uses os.Logger (subsystem + category) so logs appear in Xcode console and
//  Console.app with full filtering support.
//
//  Usage:
//    AppLogger.dashboard.info("Tapped Start AI Lesson  topic=\(topic)")
//    AppLogger.network.error("API call failed  \(error.localizedDescription)")
//

import Foundation
import os.log

enum AppLogger {

    // MARK: - Feature Loggers

    /// Home / Dashboard screen actions
    static let dashboard  = Logger(subsystem: "com.smarttutor.app", category: "Dashboard")

    /// Mock Tests list and detail
    static let mockTests  = Logger(subsystem: "com.smarttutor.app", category: "MockTests")

    /// Syllabus Map browsing
    static let syllabus   = Logger(subsystem: "com.smarttutor.app", category: "SyllabusMap")

    /// Formula Sheets browsing and search
    static let formula    = Logger(subsystem: "com.smarttutor.app", category: "FormulaSheets")

    /// Camera / photo picker for question images
    static let camera     = Logger(subsystem: "com.smarttutor.app", category: "CameraInput")

    /// Voice / mic input from search bar
    static let voice      = Logger(subsystem: "com.smarttutor.app", category: "VoiceInput")

    /// Study (chat) screen and AI ask flow
    static let study      = Logger(subsystem: "com.smarttutor.app", category: "Study")

    /// Tab and sheet navigation events
    static let navigation = Logger(subsystem: "com.smarttutor.app", category: "Navigation")

    /// All outbound API calls and responses
    static let network    = Logger(subsystem: "com.smarttutor.app", category: "Network")

    /// Auth, session, profile
    static let auth       = Logger(subsystem: "com.smarttutor.app", category: "Auth")

    /// Offline packs and Core Data sync
    static let offline    = Logger(subsystem: "com.smarttutor.app", category: "OfflinePacks")

    /// Mock test full-paper session (timer, answers, auto-save, submit)
    static let mockSession = Logger(subsystem: "com.smarttutor.app", category: "MockTestSession")

    /// Learner progress loading and reconnect refresh
    static let progress   = Logger(subsystem: "com.smarttutor.app", category: "Progress")

    /// Parent dashboard — weekly summary, alerts, exam readiness
    static let parent     = Logger(subsystem: "com.smarttutor.app", category: "ParentDashboard")

    // MARK: - Convenience Helpers

    /// Log a user-initiated tap action with the feature category it belongs to.
    static func userAction(_ logger: Logger, action: String, context: String = "") {
        if context.isEmpty {
            logger.info("👆 user-action: \(action, privacy: .public)")
        } else {
            logger.info("👆 user-action: \(action, privacy: .public)  ctx=\(context, privacy: .public)")
        }
    }

    /// Log an API call start.
    static func apiStart(_ logger: Logger, endpoint: String) {
        logger.info("🌐 api-start: \(endpoint, privacy: .public)")
    }

    /// Log a successful API response.
    static func apiSuccess(_ logger: Logger, endpoint: String, detail: String = "") {
        if detail.isEmpty {
            logger.info("✅ api-success: \(endpoint, privacy: .public)")
        } else {
            logger.info("✅ api-success: \(endpoint, privacy: .public)  \(detail, privacy: .public)")
        }
    }

    /// Log an API or feature error.
    static func apiFailure(_ logger: Logger, endpoint: String, error: Error) {
        logger.error("❌ api-failure: \(endpoint, privacy: .public)  error=\(error.localizedDescription, privacy: .public)")
    }

    /// Log navigation to a named destination.
    static func navigated(to destination: String, from source: String = "") {
        if source.isEmpty {
            navigation.info("🗺️ navigate: → \(destination, privacy: .public)")
        } else {
            navigation.info("🗺️ navigate: \(source, privacy: .public) → \(destination, privacy: .public)")
        }
    }
}
