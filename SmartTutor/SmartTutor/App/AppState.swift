//
//  AppState.swift
//  SmartTutor
//
//  Sprint 5 — Global session state injected as an EnvironmentObject.
//
//  Responsibilities:
//    • Holds the current StudentProfile (nil = logged out).
//    • Provides login(email:password:) and logout() that coordinate
//      APIClient, TokenStore, and StudentProfile Keychain persistence.
//    • Injected at root so any View can observe isAuthenticated without
//      passing state through the view hierarchy.
//    • Logs every state transition for traceability.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "AppState")

@MainActor
final class AppState: ObservableObject {

    // MARK: Published

    @Published private(set) var currentProfile: StudentProfile?
    @Published private(set) var isLoggingIn: Bool = false
    @Published private(set) var loginError: String? = nil

    var isAuthenticated: Bool { currentProfile != nil }

    // MARK: Dependencies

    private let apiClient: APIClient

    // MARK: Init

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
        // Restore session from Keychain on cold start
        currentProfile = StudentProfile.load()
        logger.info("AppState: restored  authenticated=\(self.isAuthenticated)  id=\(self.currentProfile?.id ?? "none")")
    }

    // MARK: - Login

    func login(email: String, password: String) async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError  = nil
        logger.info("AppState.login: start  email=\(email)")

        do {
            // 1. Exchange credentials for tokens (tokens auto-saved in Keychain by APIClient)
            _ = try await apiClient.login(email: email, password: password)

            // 2. Fetch profile using the fresh access token
            let serverProfile: StudentResponse = try await apiClient.request(.me)
            let profile = StudentProfile(from: serverProfile)
            profile.save()
            currentProfile = profile

            logger.info("AppState.login: success  id=\(profile.id)  premium=\(profile.isPremium)")
        } catch let error as APIError {
            loginError = error.userMessage
            logger.error("AppState.login: failed  error=\(error.localizedDescription ?? "")")
        } catch {
            loginError = "Login failed. Please try again."
            logger.error("AppState.login: unexpected  error=\(error.localizedDescription)")
        }

        isLoggingIn = false
    }

    // MARK: - Logout

    func logout() {
        logger.info("AppState.logout  id=\(self.currentProfile?.id ?? "none")")
        TokenStore.clearAll()
        StudentProfile.clear()
        currentProfile = nil
        loginError = nil
    }

    // MARK: - Handle unauthorized (called by Views on .error("unauthorized"))

    func handleSessionExpiry() {
        logger.warning("AppState.handleSessionExpiry — forcing logout")
        logout()
    }
}
