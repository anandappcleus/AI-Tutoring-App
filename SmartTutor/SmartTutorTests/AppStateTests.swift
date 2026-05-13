//
//  AppStateTests.swift
//  SmartTutorTests
//
//  Sprint 5 — Unit tests for AppState session management.
//

import XCTest
@testable import SmartTutor

@MainActor
final class AppStateTests: XCTestCase {

    var mockAPI: MockAPIClient!
    var sut: AppState!

    override func setUp() async throws {
        // Clear Keychain + profile before each test for isolation
        TokenStore.clearAll()
        StudentProfile.clear()
        mockAPI = MockAPIClient()
        sut = AppState(apiClient: mockAPI)
    }

    override func tearDown() async throws {
        TokenStore.clearAll()
        StudentProfile.clear()
    }

    // MARK: - Initial state

    func test_initial_isNotAuthenticated_whenNoStoredProfile() {
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentProfile)
    }

    func test_initial_isNotLoggingIn() {
        XCTAssertFalse(sut.isLoggingIn)
    }

    func test_initial_loginError_isNil() {
        XCTAssertNil(sut.loginError)
    }

    // MARK: - logout

    func test_logout_clearsProfile() async throws {
        // Manually set a profile as if logged in
        let profile = StudentProfile(
            id: "test-id", name: "Test", email: "t@t.com",
            preferredLanguage: .english, examTarget: .jee, isPremium: false
        )
        profile.save()
        // Reload appState to pick up saved profile
        let loggedInState = AppState(apiClient: mockAPI)
        XCTAssertTrue(loggedInState.isAuthenticated)

        loggedInState.logout()
        XCTAssertFalse(loggedInState.isAuthenticated)
        XCTAssertNil(loggedInState.currentProfile)
    }

    func test_logout_clearsTokens() {
        TokenStore.saveAccessToken("test-access")
        TokenStore.saveRefreshToken("test-refresh")
        sut.logout()
        XCTAssertNil(TokenStore.accessToken())
        XCTAssertNil(TokenStore.refreshToken())
    }

    // MARK: - handleSessionExpiry

    func test_handleSessionExpiry_logsOut() async throws {
        let profile = StudentProfile(
            id: "exp-id", name: "Exp", email: "e@e.com",
            preferredLanguage: .bengali, examTarget: .neet, isPremium: false
        )
        profile.save()
        let state = AppState(apiClient: mockAPI)
        state.handleSessionExpiry()
        XCTAssertFalse(state.isAuthenticated)
    }
}
