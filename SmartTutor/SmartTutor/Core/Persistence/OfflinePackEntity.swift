//
//  OfflinePackEntity.swift
//  SmartTutor
//
//  Sprint 8 — Core Data entities for offline question packs.
//
//  Defined entirely in code (no .xcdatamodeld) — consistent with QuizAnswerEntity.
//  These entities are registered in NSManagedObjectModel.smartTutorModel().
//
//  Entities:
//    OfflinePackEntity     — metadata for a downloaded pack
//    OfflineQuestionEntity — individual question belonging to a pack
//

import CoreData
import Foundation

// MARK: - Entity descriptions (registered from smartTutorModel)

extension NSManagedObjectModel {

    /// Returns entity descriptions for OfflinePack + OfflineQuestion.
    /// Called from smartTutorModel() to include them in the unified model.
    static func offlinePackEntities() -> [NSEntityDescription] {
        func attr(
            _ name: String,
            type: NSAttributeType,
            optional: Bool = false,
            defaultValue: Any? = nil
        ) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name          = name
            a.attributeType = type
            a.isOptional    = optional
            if let dv = defaultValue { a.defaultValue = dv }
            return a
        }

        // ── OfflinePackEntity ─────────────────────────────────────────
        let packEntity = NSEntityDescription()
        packEntity.name                   = "OfflinePackEntity"
        packEntity.managedObjectClassName = NSStringFromClass(OfflinePackEntity.self)
        packEntity.properties = [
            attr("packId",        type: .stringAttributeType),
            attr("subject",       type: .stringAttributeType),
            attr("topic",         type: .stringAttributeType),
            attr("examTarget",    type: .stringAttributeType),
            attr("language",      type: .stringAttributeType),
            attr("questionCount", type: .integer32AttributeType),
            attr("sizeKB",        type: .integer32AttributeType),
            attr("iconName",      type: .stringAttributeType),
            attr("downloadedAt",  type: .dateAttributeType, optional: true),
        ]

        // ── OfflineQuestionEntity ─────────────────────────────────────
        let questionEntity = NSEntityDescription()
        questionEntity.name                   = "OfflineQuestionEntity"
        questionEntity.managedObjectClassName = NSStringFromClass(OfflineQuestionEntity.self)
        questionEntity.properties = [
            attr("questionId",    type: .stringAttributeType),
            attr("packId",        type: .stringAttributeType),
            attr("topic",         type: .stringAttributeType),
            attr("subject",       type: .stringAttributeType),
            attr("questionText",  type: .stringAttributeType),
            attr("answerText",    type: .stringAttributeType),
            attr("language",      type: .stringAttributeType),
        ]

        return [packEntity, questionEntity]
    }
}

// MARK: - OfflinePackEntity

@objc(OfflinePackEntity)
public final class OfflinePackEntity: NSManagedObject {
    @NSManaged public var packId:        String
    @NSManaged public var subject:       String
    @NSManaged public var topic:         String
    @NSManaged public var examTarget:    String
    @NSManaged public var language:      String
    @NSManaged public var questionCount: Int32
    @NSManaged public var sizeKB:        Int32
    @NSManaged public var iconName:      String
    @NSManaged public var downloadedAt:  Date?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OfflinePackEntity> {
        NSFetchRequest<OfflinePackEntity>(entityName: "OfflinePackEntity")
    }
}

// MARK: - OfflineQuestionEntity

@objc(OfflineQuestionEntity)
public final class OfflineQuestionEntity: NSManagedObject {
    @NSManaged public var questionId:   String
    @NSManaged public var packId:       String
    @NSManaged public var topic:        String
    @NSManaged public var subject:      String
    @NSManaged public var questionText: String
    @NSManaged public var answerText:   String
    @NSManaged public var language:     String

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OfflineQuestionEntity> {
        NSFetchRequest<OfflineQuestionEntity>(entityName: "OfflineQuestionEntity")
    }
}

// MARK: - NSManagedObjectContext helpers

extension NSManagedObjectContext {

    /// Save a downloaded pack + its questions atomically.
    func savePack(
        packId: String,
        subject: String,
        topic: String,
        examTarget: String,
        language: String,
        questionCount: Int32,
        sizeKB: Int32,
        iconName: String,
        questions: [(id: String, topic: String, subject: String, questionText: String, answerText: String, language: String)]
    ) {
        let pack = OfflinePackEntity(context: self)
        pack.packId        = packId
        pack.subject       = subject
        pack.topic         = topic
        pack.examTarget    = examTarget
        pack.language      = language
        pack.questionCount = questionCount
        pack.sizeKB        = sizeKB
        pack.iconName      = iconName
        pack.downloadedAt  = Date()

        for q in questions {
            let entity = OfflineQuestionEntity(context: self)
            entity.questionId   = q.id
            entity.packId       = packId
            entity.topic        = q.topic
            entity.subject      = q.subject
            entity.questionText = q.questionText
            entity.answerText   = q.answerText
            entity.language     = q.language
        }
    }

    /// Fetch all downloaded pack IDs.
    func fetchDownloadedPackIds() -> Set<String> {
        let request = OfflinePackEntity.fetchRequest()
        let packs = (try? fetch(request)) ?? []
        return Set(packs.map(\.packId))
    }

    /// Fetch all downloaded packs as full entities, newest first.
    /// Used for offline fallback when the server is unreachable.
    func fetchAllDownloadedPacks() -> [OfflinePackEntity] {
        let request = OfflinePackEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "downloadedAt", ascending: false)]
        return (try? fetch(request)) ?? []
    }

    /// Delete a pack and all its questions.
    func deletePack(packId: String) {
        let pRequest = OfflinePackEntity.fetchRequest()
        pRequest.predicate = NSPredicate(format: "packId == %@", packId)
        (try? fetch(pRequest))?.forEach { delete($0) }

        let qRequest = OfflineQuestionEntity.fetchRequest()
        qRequest.predicate = NSPredicate(format: "packId == %@", packId)
        (try? fetch(qRequest))?.forEach { delete($0) }
    }

    /// Fetch all questions for a given pack, ordered by questionId.
    func fetchQuestions(for packId: String) -> [OfflineQuestionEntity] {
        let request = OfflineQuestionEntity.fetchRequest()
        request.predicate     = NSPredicate(format: "packId == %@", packId)
        request.sortDescriptors = [NSSortDescriptor(key: "questionId", ascending: true)]
        return (try? fetch(request)) ?? []
    }
}
