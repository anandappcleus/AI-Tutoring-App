//
//  QuizAnswerEntity.swift
//  SmartTutor
//
//  Sprint 5 — NSManagedObject subclass for the offline answer queue.
//
//  Defined entirely in code so there is no .xcdatamodeld binary to manage.
//  CoreDataStack registers this entity programmatically before loading the store.
//
//  Schema:
//    id          UUID      (primary key, generated locally)
//    question    String
//    topic       String?
//    subject     String?
//    isCorrect   Bool
//    answeredAt  Date
//    synced      Bool      (false = pending upload to /sync-answers)
//

import CoreData
import Foundation

// MARK: - Entity description (registered at runtime)

extension NSManagedObjectModel {
    /// Build the managed object model for SmartTutor entirely in code.
    /// Call this before loading the persistent store.
    static func smartTutorModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name                 = "QuizAnswerEntity"
        entity.managedObjectClassName = NSStringFromClass(QuizAnswerEntity.self)

        func attr(_ name: String, type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name          = name
            a.attributeType = type
            a.isOptional    = optional
            return a
        }

        entity.properties = [
            attr("id",          type: .UUIDAttributeType),
            attr("question",    type: .stringAttributeType),
            attr("topic",       type: .stringAttributeType,  optional: true),
            attr("subject",     type: .stringAttributeType,  optional: true),
            attr("isCorrect",   type: .booleanAttributeType),
            attr("answeredAt",  type: .dateAttributeType),
            attr("synced",      type: .booleanAttributeType),
        ]

        model.entities = [entity]
        return model
    }
}

// MARK: - Managed Object Subclass

@objc(QuizAnswerEntity)
public final class QuizAnswerEntity: NSManagedObject {
    @NSManaged public var id:          UUID?
    @NSManaged public var question:    String
    @NSManaged public var topic:       String?
    @NSManaged public var subject:     String?
    @NSManaged public var isCorrect:   Bool
    @NSManaged public var answeredAt:  Date
    @NSManaged public var synced:      Bool

    @nonobjc public class func fetchRequest() -> NSFetchRequest<QuizAnswerEntity> {
        NSFetchRequest<QuizAnswerEntity>(entityName: "QuizAnswerEntity")
    }

    /// Convert to the Codable payload the sync API expects.
    func toSyncPayload() -> SyncAnswerPayload {
        SyncAnswerPayload(
            question:   question,
            topic:      topic,
            subject:    subject,
            isCorrect:  isCorrect,
            answeredAt: answeredAt
        )
    }
}
