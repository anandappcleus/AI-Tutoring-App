//
//  ParentDashboardViewModelTests.swift
//  SmartTutorTests
//
//  Sprint 6 — Unit tests for ParentDashboardViewModel.
//
//  Coverage:
//    ✓ Initial computed properties return zero/empty defaults
//    ✓ questionsAttempted maps from progressData.totalQuestions
//    ✓ avgAccuracy maps from progressData.overallAccuracyPct (truncated to Int)
//    ✓ weakTopics maps from progressData.weakTopics
//    ✓ topicBreakdown maps from progressData.topics
//    ✓ weekRange formats "weekStart – weekEnd" correctly
//    ✓ weekRange is nil when no data loaded
//    ✓ load() failure sets errorMessage
//

import XCTest
@testable import SmartTutor

@MainActor
final class ParentDashboardViewModelTests: XCTestCase {

    var stubAPI: StubAPIClient!
    var sut: ParentDashboardViewModel!

    override func setUp() async throws {
        stubAPI = StubAPIClient()
        sut = ParentDashboardViewModel(apiClient: stubAPI)
    }

    // MARK: - Initial computed properties

    func test_initial_questionsAttempted_isZero() {
        XCTAssertEqual(sut.questionsAttempted, 0)
    }

    func test_initial_avgAccuracy_isZero() {
        XCTAssertEqual(sut.avgAccuracy, 0)
    }

    func test_initial_weakTopics_isEmpty() {
        XCTAssertTrue(sut.weakTopics.isEmpty)
    }

    func test_initial_topicBreakdown_isEmpty() {
        XCTAssertTrue(sut.topicBreakdown.isEmpty)
    }

    func test_initial_weekRange_isNil() {
        XCTAssertNil(sut.weekRange)
    }

    // MARK: - Computed property mapping after load

    func test_questionsAttempted_mapsFromProgressData() async {
        stubAPI.responseHandler = { _ in makeProgressResponse(totalQuestions: 42) }
        await sut.load(studentId: "s1")
        XCTAssertEqual(sut.questionsAttempted, 42)
    }

    func test_avgAccuracy_mapsFromProgressData_truncatedToInt() async {
        stubAPI.responseHandler = { _ in makeProgressResponse(overallAccuracyPct: 73.9) }
        await sut.load(studentId: "s1")
        XCTAssertEqual(sut.avgAccuracy, 73)   // Int(73.9) == 73
    }

    func test_weakTopics_mapsFromProgressData() async {
        let weak = ["Optics", "Electrochemistry"]
        stubAPI.responseHandler = { _ in makeProgressResponse(weakTopics: weak) }
        await sut.load(studentId: "s1")
        XCTAssertEqual(sut.weakTopics, weak)
    }

    func test_topicBreakdown_mapsFromProgressData() async {
        let topic = ProgressResponse.TopicProgress(
            topic: "Mechanics", subject: "Physics",
            correct: 8, total: 10, accuracyPct: 80.0
        )
        stubAPI.responseHandler = { _ in makeProgressResponse(topics: [topic]) }
        await sut.load(studentId: "s1")
        XCTAssertEqual(sut.topicBreakdown.count, 1)
        XCTAssertEqual(sut.topicBreakdown.first?.topic, "Mechanics")
        XCTAssertEqual(sut.topicBreakdown.first?.accuracyPct, 80.0, accuracy: 0.01)
    }

    func test_weekRange_formattedCorrectly() async {
        stubAPI.responseHandler = { _ in
            makeProgressResponse(weekStart: "2026-05-08", weekEnd: "2026-05-14")
        }
        await sut.load(studentId: "s1")
        XCTAssertEqual(sut.weekRange, "2026-05-08 – 2026-05-14")
    }

    func test_weekRange_isNilBeforeLoad() {
        XCTAssertNil(sut.weekRange)
    }

    // MARK: - Failure

    func test_load_failure_setsErrorMessage() async {
        stubAPI.responseHandler = { _ in throw APIError.serverError(statusCode: 500, body: "error") }
        await sut.load(studentId: "s1")
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertNil(sut.progressData)
    }

    func test_load_failure_clearsIsLoading() async {
        stubAPI.responseHandler = { _ in throw APIError.noNetwork }
        await sut.load(studentId: "s1")
        XCTAssertFalse(sut.isLoading)
    }
}
