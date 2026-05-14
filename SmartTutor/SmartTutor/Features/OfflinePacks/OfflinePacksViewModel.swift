//
//  OfflinePacksViewModel.swift
//  SmartTutor
//
//  Sprint 8 — ViewModel for OfflinePacksView.
//
//  Responsibilities:
//    • Loads pack catalog from GET /packs (authenticated).
//    • Cross-references with Core Data to determine which packs are downloaded.
//    • Downloads packs via GET /packs/:id/download and saves to Core Data.
//    • Deletes downloaded packs from Core Data.
//    • Exposes download progress per pack (0.0 → 1.0) for animated progress bar.
//

import Combine
import CoreData
import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "OfflinePacksViewModel")

// MARK: - View-model item

struct PackListItem: Identifiable {
    let id: String           // server pack ID
    let subject: String
    let topic: String
    let questionCount: Int
    let sizeKB: Int
    let iconName: String     // SF Symbol name
    let subjectColor: Color
    var isDownloaded: Bool

    /// Human-readable size string.
    var sizeDisplay: String {
        sizeKB < 1000
            ? "\(sizeKB) KB"
            : String(format: "%.1f MB", Double(sizeKB) / 1000.0)
    }

    init(response: PackResponse, isDownloaded: Bool) {
        self.id            = response.id
        self.subject       = response.subject
        self.topic         = response.topic
        self.questionCount = response.questionCount
        self.sizeKB        = response.sizeKB
        self.iconName      = response.iconName
        self.subjectColor  = PackListItem.colorForSubject(response.subject)
        self.isDownloaded  = isDownloaded
    }

    private static func colorForSubject(_ subject: String) -> Color {
        switch subject.lowercased() {
        case "physics":     return .blue
        case "chemistry":   return .green
        default:            return .purple
        }
    }
}

// MARK: - ViewModel

@MainActor
final class OfflinePacksViewModel: ObservableObject {

    @Published private(set) var packs: [PackListItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var downloadingPackId: String? = nil
    @Published private(set) var downloadProgress: [String: Double] = [:]

    var downloadedPacks: [PackListItem] { packs.filter(\.isDownloaded) }
    var availablePacks: [PackListItem]  { packs.filter { !$0.isDownloaded } }
    var usedKB: Int                     { downloadedPacks.reduce(0) { $0 + $1.sizeKB } }

    private let apiClient: APIClient
    private let coreData: CoreDataStack

    init(apiClient: APIClient = .shared, coreData: CoreDataStack = .shared) {
        self.apiClient = apiClient
        self.coreData  = coreData
    }

    // MARK: - Load catalog

    func loadPacks() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        logger.info("OfflinePacksViewModel.loadPacks: start")

        do {
            let serverPacks: [PackResponse] = try await apiClient.request(.packs)
            let downloadedIds = coreData.viewContext.fetchDownloadedPackIds()
            packs = serverPacks.map { PackListItem(response: $0, isDownloaded: downloadedIds.contains($0.id)) }
            logger.info("OfflinePacksViewModel.loadPacks: loaded \(serverPacks.count) packs, \(downloadedIds.count) downloaded")
        } catch let error as APIError {
            errorMessage = error.userMessage
            logger.error("OfflinePacksViewModel.loadPacks: \(error.localizedDescription ?? "")")
        } catch {
            errorMessage = "Failed to load packs."
            logger.error("OfflinePacksViewModel.loadPacks: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Download pack

    func download(_ pack: PackListItem) async {
        guard downloadingPackId == nil else { return }
        downloadingPackId = pack.id
        downloadProgress[pack.id] = 0.15
        logger.info("OfflinePacksViewModel.download: start  pack_id=\(pack.id)")

        do {
            // Simulate a brief pre-flight delay so the progress bar is visible
            downloadProgress[pack.id] = 0.35

            let response: PackDownloadResponse = try await apiClient.request(.downloadPack(id: pack.id))
            downloadProgress[pack.id] = 0.80

            // Persist to Core Data
            let ctx = coreData.viewContext
            ctx.savePack(
                packId:        pack.id,
                subject:       pack.subject,
                topic:         pack.topic,
                examTarget:    "JEE",   // server packs are JEE for now
                language:      "bn",
                questionCount: Int32(response.questions.count),
                sizeKB:        Int32(pack.sizeKB),
                iconName:      pack.iconName,
                questions: response.questions.map {
                    (id: $0.id, topic: $0.topic, subject: $0.subject,
                     questionText: $0.questionText, answerText: $0.answerText, language: $0.language)
                }
            )
            coreData.saveViewContext()
            downloadProgress[pack.id] = 1.0

            // Update in-memory state
            if let idx = packs.firstIndex(where: { $0.id == pack.id }) {
                packs[idx].isDownloaded = true
            }
            logger.info("OfflinePacksViewModel.download: saved  pack_id=\(pack.id)  questions=\(response.questions.count)")
        } catch let error as APIError {
            errorMessage = error.userMessage
            logger.error("OfflinePacksViewModel.download: failed  pack_id=\(pack.id)  error=\(error.localizedDescription ?? "")")
        } catch {
            errorMessage = "Download failed. Please try again."
            logger.error("OfflinePacksViewModel.download: unexpected  pack_id=\(pack.id)  error=\(error.localizedDescription)")
        }

        downloadingPackId = nil
        downloadProgress.removeValue(forKey: pack.id)
    }

    // MARK: - Delete pack

    func deletePack(_ pack: PackListItem) {
        logger.info("OfflinePacksViewModel.deletePack: pack_id=\(pack.id)")
        let ctx = coreData.viewContext
        ctx.deletePack(packId: pack.id)
        coreData.saveViewContext()

        if let idx = packs.firstIndex(where: { $0.id == pack.id }) {
            packs[idx].isDownloaded = false
        }
    }
}
