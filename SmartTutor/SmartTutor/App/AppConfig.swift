//
//  AppConfig.swift
//  SmartTutor
//
//  Sprint 1, Task 10 — API environment configuration.
//
//  Copilot prompt used to generate this file:
//  // Enum BuildEnvironment with cases debug and release
//  // Computed var apiBaseURL: URL — debug -> localhost:8000, release -> Info.plist "API_BASE_URL"
//  // static var current: BuildEnvironment { #if DEBUG .debug #else .release }
//

import Foundation

enum BuildEnvironment {
    case debug
    case release

    static var current: BuildEnvironment {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    var apiBaseURL: URL {
        switch self {
        case .debug:
            // Simulator can't reach localhost — always point at the live Railway API.
            // Physical device debug builds also use Railway so you can test without
            // running a local server.
            #if targetEnvironment(simulator)
            return URL(string: "https://smarttutor-api-production.up.railway.app")!
            #else
            return URL(string: "http://localhost:8000")!
            #endif

        case .release:
            // API_BASE_URL can be overridden via Release xcconfig / Info.plist.
            // Falls back to the live Railway deployment.
            let urlString = Bundle.main.infoDictionary?["API_BASE_URL"] as? String
                ?? "https://smarttutor-api-production.up.railway.app"
            return URL(string: urlString)!
        }
    }
}

enum AppConfig {
    static let apiBaseURL = BuildEnvironment.current.apiBaseURL
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
}
