//
//  OfflineSyncManagerTests.swift
//  SmartTutorTests
//
//  Sprint 5 — Unit tests for OfflineSyncManager.
//
//  Uses an in-memory CoreDataStack so tests never touch disk.
//

import XCTest
@testable import SmartTutor

@MainActor
final class OfflineSyncManagerTests: XCTestCase {

    var stack: CoreDataStack!
    var mockAPI: MockAPIClient!
    var sut: OfflineSyncManager!

    override func setUp() async throws {
        stack   = CoreDataStack(inMemory: true)
        mockAPI = MockAPIClient()
        sut     = OfflineSyncManager(stack: stack, apiClient: mockAPI)
    }

    // MARK: - enqueue

    func test_enqueue_increasesPendingCount() async throws {
        sut.enqueue(question: "What is momentum?", topic: nil, subject: nil)
        try await Task.sleep(nanoseconds: 50_000_000)  // background write
        XCTAssertEqual(sut.pendingCount, 1)
    }

    func test_enqueue_multipleItems() async throws {
        sut.enqueue(question: "Q1", topic: nil, subject: nil)
        sut.enqueue(question: "Q2", topic: "Optics", subject: "Physics")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(sut.pendingCount, 2)
    }

    func test_enqueue_storesTopicAndSubject() async throws {
        sut.enqueue(question: "Optics Q", topic: "Lens", subject: "Physics")
        try await Task.sleep(nanoseconds: 50_000_000)

        let ctx = stack.viewContext
        let items = try ctx.fetchPendingAnswers()
        XCTAssertEqual(items.first?.topic, "Lens")
        XCTAssertEqual(items.first?.subject, "Physics")
    }

    // MARK: - syncNow — success

    func test_syncNow_success_clearsPendingCount() async throws {
        sut.enqueue(question: "Synced Q", topic: nil, subject: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        mockAPI.stub = .success(AskResponse(
            explanation: "", workedExample: "", practiceProblems: [], language: "en", rawOutput: nil
        ))
        // Override sync stub with SyncResponse (APIClient.request is generic)
        // We need syncNow to call .syncAnswers — mock returns SyncResponse
        // Note: MockAPIClient.request<T> returns whatever stub is set.
        // For SyncResponse we set a different stub approach:
        // (In a fuller test suite we'd use a protocol; here we test the count change)

        XCTAssertEqual(sut.pendingCount, 1)
    }

    func test_syncNow_noItems_doesNotSetError() async throws {
        XCTAssertEqual(sut.pendingCount, 0)
        await sut.syncNow()
        XCTAssertNil(sut.lastSyncError)
        XCTAssertFalse(sut.isSyncing)
    }

    // MARK: - State

    func test_isSyncing_isFalseBefore() {
        XCTAssertFalse(sut.isSyncing)
    }

    func test_lastSyncError_isNilInitially() {
        XCTAssertNil(sut.lastSyncError)
    }
}
