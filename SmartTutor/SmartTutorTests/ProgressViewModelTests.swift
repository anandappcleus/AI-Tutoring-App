//
//  ProgressViewModelTests.swift
//  SmartTutorTests
//
//  Sprint 6 — Unit tests for ProgressViewModel.
//
//  Coverage:
//    ✓ Initial state: no data, not loading, no error
//    ✓ load() populates progressData on success
//    ✓ load() clears isLoading after success
//    ✓ load() sets errorMessage on APIError
//    ✓ load() sets errorMessage on unexpected error
//    ✓ load() clears previous errorMessage on retry
//    ✓ load() correctly maps totalQuestions and overallAccuracyPct
//

import XCTest
@testable import SmartTutor

@MainActor
final class ProgressViewModelTests: XCTestCase {

    var stubAPI: StubAPIClient!
    var sut: ProgressViewModel!

    override func setUp() async throws {
        stubAPI = StubAPIClient()
        sut = ProgressViewModel(apiClient: stubAPI)
    }

    // MARK: - Initial state

    func test_initial_progressDataIsNil() {
        XCTAssertNil(sut.progressData)
    }

    func test_initial_isNotLoading() {
        XCTAssertFalse(sut.isLoading)
    }

    func test_initial_errorMessageIsNil() {
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - load() — success

    func test_load_success_populatesProgressData() async {
        let response = makeProgressResponse(totalQuestions: 20, overallAccuracyPct: 80.0)
        stubAPI.responseHandler = { _ in response }

        await sut.load(studentId: "student-1")

        XCTAssertNotNil(sut.progressData)
        XCTAssertEqual(sut.progressData?.totalQuestions, 20)
    }

    func test_load_success_setsCorrectAccuracy() async {
        let response = makeProgressResponse(overallAccuracyPct: 65.5)
        stubAPI.responseHandler = { _ in response }

        await sut.load(studentId: "student-1")

        XCTAssertEqual(sut.progressData?.overallAccuracyPct, 65.5, accuracy: 0.01)
    }

    func test_load_success_clearsIsLoading() async {
        stubAPI.responseHandler = { _ in makeProgressResponse() }

        await sut.load(studentId: "student-1")

        XCTAssertFalse(sut.isLoading)
    }

    func test_load_success_clearsErrorMessage() async {
        // Pre-seed an error
        stubAPI.responseHandler = { _ in throw APIError.noNetwork }
        await sut.load(studentId: "student-1")
        XCTAssertNotNil(sut.errorMessage)

        // Retry with success — error should be cleared
        stubAPI.responseHandler = { _ in makeProgressResponse() }
        await sut.load(studentId: "student-1")
        XCTAssertNil(sut.errorMessage)
    }

    func test_load_success_populatesWeakTopics() async {
        let response = makeProgressResponse(weakTopics: ["Organic Chemistry", "Thermodynamics"])
        stubAPI.responseHandler = { _ in response }

        await sut.load(studentId: "student-1")

        XCTAssertEqual(sut.progressData?.weakTopics, ["Organic Chemistry", "Thermodynamics"])
    }

    // MARK: - load() — failure

    func test_load_apiError_noNetwork_setsErrorMessage() async {
        stubAPI.responseHandler = { _ in throw APIError.noNetwork }

        await sut.load(studentId: "student-1")

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.progressData)
    }

    func test_load_apiError_unauthorized_setsErrorMessage() async {
        stubAPI.responseHandler = { _ in throw APIError.unauthorized }

        await sut.load(studentId: "student-1")

        XCTAssertNotNil(sut.errorMessage)
    }

    func test_load_unexpectedError_setsErrorMessage() async {
        stubAPI.responseHandler = { _ in throw URLError(.timedOut) }

        await sut.load(studentId: "student-1")

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - API call count

    func test_load_makesExactlyOneAPICall() async {
        stubAPI.responseHandler = { _ in makeProgressResponse() }

        await sut.load(studentId: "student-1")

        XCTAssertEqual(stubAPI.callCount, 1)
    }
}
