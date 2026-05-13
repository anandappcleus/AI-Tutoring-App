//
//  CoreDataStackTests.swift
//  SmartTutorTests
//
//  Sprint 5 — Unit tests for Core Data entity helpers.
//

import CoreData
import XCTest
@testable import SmartTutor

final class CoreDataStackTests: XCTestCase {

    var stack: CoreDataStack!

    override func setUp() {
        stack = CoreDataStack(inMemory: true)
    }

    // MARK: - insertPendingAnswer

    func test_insertPendingAnswer_hasCorrectDefaults() {
        let ctx = stack.viewContext
        let entity = ctx.insertPendingAnswer(question: "What is velocity?")
        XCTAssertEqual(entity.question, "What is velocity?")
        XCTAssertFalse(entity.synced)
        XCTAssertTrue(entity.isCorrect)  // open Q&A default
        XCTAssertNotNil(entity.id)
    }

    func test_insertPendingAnswer_storesOptionalFields() {
        let ctx = stack.viewContext
        let entity = ctx.insertPendingAnswer(
            question: "What is refraction?",
            topic: "Optics",
            subject: "Physics"
        )
        XCTAssertEqual(entity.topic, "Optics")
        XCTAssertEqual(entity.subject, "Physics")
    }

    // MARK: - fetchPendingAnswers

    func test_fetchPendingAnswers_returnsUnsyncedOnly() throws {
        let ctx = stack.viewContext
        let pending = ctx.insertPendingAnswer(question: "Pending Q")

        let synced = ctx.insertPendingAnswer(question: "Already synced")
        synced.synced = true

        stack.saveViewContext()

        let results = try ctx.fetchPendingAnswers()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].question, "Pending Q")
        _ = pending  // silence unused warning
    }

    func test_fetchPendingAnswers_orderedOldestFirst() throws {
        let ctx = stack.viewContext
        let older = ctx.insertPendingAnswer(question: "Older")
        older.answeredAt = Date(timeIntervalSinceNow: -100)

        let newer = ctx.insertPendingAnswer(question: "Newer")
        newer.answeredAt = Date()

        stack.saveViewContext()

        let results = try ctx.fetchPendingAnswers()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].question, "Older")
        XCTAssertEqual(results[1].question, "Newer")
    }

    // MARK: - toSyncPayload

    func test_toSyncPayload_mapsAllFields() {
        let ctx = stack.viewContext
        let entity = ctx.insertPendingAnswer(
            question: "Payload Q",
            topic: "Waves",
            subject: "Physics",
            isCorrect: true
        )
        let payload = entity.toSyncPayload()
        XCTAssertEqual(payload.question, "Payload Q")
        XCTAssertEqual(payload.topic, "Waves")
        XCTAssertEqual(payload.subject, "Physics")
        XCTAssertTrue(payload.isCorrect)
    }

    // MARK: - save

    func test_save_returnsTrueOnSuccess() {
        let ctx = stack.viewContext
        _ = ctx.insertPendingAnswer(question: "Save test")
        let result = stack.save(ctx)
        XCTAssertTrue(result)
    }

    func test_save_noChanges_returnsTrue() {
        let result = stack.save(stack.viewContext)
        XCTAssertTrue(result)
    }
}
