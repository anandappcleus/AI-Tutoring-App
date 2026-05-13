//
//  CoreDataStack.swift
//  SmartTutor
//
//  Sprint 5 — Core Data stack for the offline quiz-answer queue.
//
//  Design (Clean Architecture):
//    • CoreDataStack owns the NSPersistentContainer and exposes a single
//      viewContext (main thread) and a background() context factory.
//    • Singleton shared instance — tests inject a custom in-memory stack
//      via CoreDataStack(inMemory: true).
//    • The single entity QuizAnswerEntity mirrors the SyncAnswerPayload
//      the backend expects so the sync layer has zero transformation logic.
//
//  Entity: QuizAnswerEntity
//    id          UUID    (locally generated, for deduplication)
//    question    String
//    topic       String? (optional — set after LLM returns)
//    subject     String? (optional)
//    isCorrect   Bool    (always true for open Q&A — tracks "attempted")
//    answeredAt  Date
//    synced      Bool    (false = pending upload)
//

import CoreData
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "CoreDataStack")

// MARK: - Stack

final class CoreDataStack {

    // MARK: Shared instance (use inMemory:true in tests)
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    /// Main-thread context — use for reads and SwiftUI bindings.
    var viewContext: NSManagedObjectContext { container.viewContext }

    // MARK: Init

    init(inMemory: Bool = false) {
        // Use the code-only model — no .xcdatamodeld binary needed.
        container = NSPersistentContainer(
            name: "SmartTutor",
            managedObjectModel: NSManagedObjectModel.smartTutorModel()
        )

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { storeDescription, error in
            if let error {
                // In production this is fatal — the app cannot function without Core Data.
                // Crash early with a clear message so the crash log is actionable.
                logger.critical("CoreDataStack: failed to load store url=\(storeDescription.url?.absoluteString ?? "nil") error=\(error.localizedDescription)")
                fatalError("CoreDataStack: persistent store load failed — \(error)")
            }
            logger.info("CoreDataStack: store loaded url=\(storeDescription.url?.absoluteString ?? "in-memory")")
        }

        // Merge remote changes into viewContext automatically
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: Background context factory

    /// Create a private-queue context for background writes.
    /// Always call save() on this context; changes are merged into viewContext.
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    // MARK: Save helpers

    /// Save viewContext if it has unsaved changes. Logs but never throws to callers.
    func saveViewContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            logger.debug("CoreDataStack: viewContext saved")
        } catch {
            logger.error("CoreDataStack: viewContext save failed — \(error.localizedDescription)")
        }
    }

    /// Save any context. Returns false and logs on failure.
    @discardableResult
    func save(_ context: NSManagedObjectContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            logger.error("CoreDataStack: save failed — \(error.localizedDescription)")
            context.rollback()
            return false
        }
    }
}

// MARK: - QuizAnswerEntity helpers

extension NSManagedObjectContext {

    /// Insert a new pending quiz answer into this context.
    @discardableResult
    func insertPendingAnswer(
        question: String,
        topic: String? = nil,
        subject: String? = nil,
        isCorrect: Bool = true,
        answeredAt: Date = Date()
    ) -> QuizAnswerEntity {
        let entity = QuizAnswerEntity(context: self)
        entity.id         = UUID()
        entity.question   = question
        entity.topic      = topic
        entity.subject    = subject
        entity.isCorrect  = isCorrect
        entity.answeredAt = answeredAt
        entity.synced     = false
        return entity
    }

    /// Fetch all unsynced answers ordered oldest-first.
    func fetchPendingAnswers() throws -> [QuizAnswerEntity] {
        let request: NSFetchRequest<QuizAnswerEntity> = QuizAnswerEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "synced == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "answeredAt", ascending: true)]
        return try fetch(request)
    }
}
