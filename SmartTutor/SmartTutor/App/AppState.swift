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
import Combine
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
        // iOS Keychain survives app deletion. On a fresh install we must wipe
        // any stale tokens/profile so the user sees the Login screen.
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            TokenStore.clearAll()
            StudentProfile.clear()
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            logger.info("AppState: fresh install — Keychain wiped")
        }
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

    // MARK: - Update Profile (called after Onboarding and from Settings)

    func updateProfile(language: String? = nil, examTarget: String? = nil, name: String? = nil) async {
        logger.info("AppState.updateProfile: start  lang=\(language ?? "-")  exam=\(examTarget ?? "-")")
        do {
            let updated: StudentResponse = try await apiClient.request(
                .updateProfile(language: language, examTarget: examTarget, name: name)
            )
            let profile = StudentProfile(from: updated)
            profile.save()
            currentProfile = profile
            logger.info("AppState.updateProfile: ok  lang=\(profile.preferredLanguage.rawValue)  exam=\(profile.examTarget.rawValue)")
        } catch {
            logger.error("AppState.updateProfile: failed  error=\(error.localizedDescription)")
        }
    }

    // MARK: - Logout

    func logout() {
        logger.info("AppState.logout  id=\(self.currentProfile?.id ?? "none")")
        TokenStore.clearAll()
        StudentProfile.clear()
        currentProfile = nil
        loginError = nil
    }

    // MARK: - Register APNs device token (called from AppDelegate)

    func registerDeviceToken(_ token: String) async {
        guard isAuthenticated else {
            logger.info("AppState.registerDeviceToken: skipped — not authenticated")
            return
        }
        logger.info("AppState.registerDeviceToken: uploading \(token.prefix(8))…")
        do {
            let _: DeviceTokenResponse = try await apiClient.request(.registerDeviceToken(token: token))
            logger.info("AppState.registerDeviceToken: ok")
        } catch {
            // Non-fatal: push notifications degrade gracefully if upload fails
            logger.error("AppState.registerDeviceToken: failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Handle unauthorized (called by Views on .error("unauthorized"))

    func handleSessionExpiry() {
        logger.warning("AppState.handleSessionExpiry — forcing logout")
        logout()
    }
}
