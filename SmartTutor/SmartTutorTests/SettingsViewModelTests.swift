//
//  SettingsViewModelTests.swift
//  SmartTutorTests
//
//  Tests for Settings-related AppState mutations:
//  language update, name update, sound effects persistence.
//

import XCTest
@testable import SmartTutor

@MainActor
final class SettingsViewModelTests: XCTestCase {

    var stub: StubAPIClient!
    var sut: AppState!

    override func setUp() async throws {
        TokenStore.clearAll()
        StudentProfile.clear()
        stub = StubAPIClient()
        sut  = AppState(apiClient: stub)

        // Seed a logged-in profile so updateProfile has a current profile to work with
        let profile = StudentProfile(
            id: "user-1", name: "Ananya", email: "ananya@example.com",
            preferredLanguage: .english, examTarget: .jee, isPremium: false
        )
        profile.save()
        TokenStore.saveAccessToken("test-token")
    }

    override func tearDown() async throws {
        TokenStore.clearAll()
        StudentProfile.clear()
        UserDefaults.standard.removeObject(forKey: "soundEffectsEnabled")
    }

    // MARK: - Language update

    func test_updateProfile_language_updatesCurrentProfile() async throws {
        let updated = makeStudentResponse(language: "hi")
        stub.responseHandler = { _ in updated }

        // Re-create sut so it picks up the saved profile
        sut = AppState(apiClient: stub)

        await sut.updateProfile(language: "hi")

        XCTAssertEqual(sut.currentProfile?.preferredLanguage, .hindi)
    }

    func test_updateProfile_language_persistsToKeychain() async throws {
        let updated = makeStudentResponse(language: "bn")
        stub.responseHandler = { _ in updated }
        sut = AppState(apiClient: stub)

        await sut.updateProfile(language: "bn")

        // Reload from Keychain to verify persistence
        let loaded = StudentProfile.load()
        XCTAssertEqual(loaded?.preferredLanguage, .bengali)
    }

    // MARK: - Name update

    func test_updateProfile_name_updatesCurrentProfile() async throws {
        let updated = makeStudentResponse(name: "Riya")
        stub.responseHandler = { _ in updated }
        sut = AppState(apiClient: stub)

        await sut.updateProfile(name: "Riya")

        XCTAssertEqual(sut.currentProfile?.name, "Riya")
    }

    // MARK: - Network failure is non-fatal

    func test_updateProfile_doesNotCrash_onNetworkFailure() async throws {
        stub.responseHandler = { _ in throw APIError.noNetwork }
        sut = AppState(apiClient: stub)

        // Should not throw — errors are logged internally
        await sut.updateProfile(language: "hi")

        // currentProfile unchanged (still has the seeded profile's language)
        XCTAssertEqual(sut.currentProfile?.preferredLanguage, .english)
    }

    // MARK: - Sound Effects (AppStorage)

    func test_soundEffects_defaultsToTrue() {
        let stored = UserDefaults.standard.object(forKey: "soundEffectsEnabled")
        // Before first write, key is absent — reads as `true` (AppStorage default)
        XCTAssertNil(stored, "Key should not be written until the user changes the toggle")
    }

    func test_soundEffects_persists_whenSet() {
        UserDefaults.standard.set(false, forKey: "soundEffectsEnabled")
        let value = UserDefaults.standard.bool(forKey: "soundEffectsEnabled")
        XCTAssertFalse(value)
    }

    // MARK: - Helpers

    private func makeStudentResponse(
        name: String = "Ananya",
        language: String = "en",
        examTarget: String = "JEE"
    ) -> StudentResponse {
        StudentResponse(
            id: "user-1",
            name: name,
            email: "ananya@example.com",
            preferredLanguage: language,
            examTarget: examTarget,
            isPremium: false,
            createdAt: "2026-01-01T00:00:00Z"
        )
    }
}
