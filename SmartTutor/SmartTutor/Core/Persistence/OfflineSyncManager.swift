//
//  OfflineSyncManager.swift
//  SmartTutor
//
//  Sprint 5 — offline answer queue with automatic sync on reconnect.
//
//  Design (Clean Architecture — Service layer):
//    • Owns a NWPathMonitor to watch network reachability.
//    • On reconnect: fetches all unsynced QuizAnswerEntity rows, POSTs them
//      to POST /sync-answers in a single batch, marks rows as synced on success.
//    • Batches are capped at maxBatchSize to avoid oversized payloads.
//    • Failures are logged and retried on the next reconnect event — no silent drops.
//    • @MainActor-isolated published state for SwiftUI observability.
//    • Dependency-injected APIClient + CoreDataStack for testability.
//

@preconcurrency import CoreData
import Foundation
import Network
import Observation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "OfflineSyncManager")

// MARK: - Protocol (for mock injection in tests)

protocol OfflineSyncManaging {
    var pendingCount: Int { get }
    func enqueue(question: String, topic: String?, subject: String?)
    func syncNow() async
}

// MARK: - Implementation

@MainActor
@Observable final class OfflineSyncManager: OfflineSyncManaging {

    /// App-wide singleton. ViewModels that need reachability or sync status
    /// should reference this rather than creating their own instance.
    static let shared = OfflineSyncManager()

    // MARK: Published state

    private(set) var pendingCount: Int = 0
    private(set) var isSyncing: Bool   = false
    private(set) var lastSyncError: String? = nil
    /// True when the device has a usable network path. KVO-observable by any View or ViewModel.
    private(set) var isNetworkReachable: Bool = false

    // MARK: Dependencies

    private let stack: CoreDataStack
    private let apiClient: APIClient

    // MARK: Private

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.smarttutor.netmonitor", qos: .utility)
    private let maxBatchSize = 50

    // MARK: Init

    init(stack: CoreDataStack = .shared, apiClient: APIClient = .shared) {
        self.stack     = stack
        self.apiClient = apiClient
        refreshPendingCount()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Public API

    /// Enqueue a quiz answer for deferred upload to the server.
    /// Thread-safe — writes on a background context.
    func enqueue(
        question: String,
        topic: String? = nil,
        subject: String? = nil
    ) {
        let ctx = stack.newBackgroundContext()
        ctx.perform {
            ctx.insertPendingAnswer(question: question, topic: topic, subject: subject)
            let saved = self.stack.save(ctx)
            logger.info("OfflineSyncManager.enqueue  saved=\(saved)  q=\(question.prefix(60))")
            Task { @MainActor in self.refreshPendingCount() }
        }
    }

    /// Attempt an immediate sync of all pending answers.
    /// No-op if already syncing or no pending items.
    func syncNow() async {
        guard !isSyncing else {
            logger.debug("OfflineSyncManager.syncNow: already syncing — skipped")
            return
        }
        await performSync()
    }

    // MARK: - Private helpers

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasUnreachable = !self.isNetworkReachable
                self.isNetworkReachable = reachable
                logger.info("OfflineSyncManager: isNetworkReachable=\(reachable)")
                logger.info("OfflineSyncManager: network=\(reachable ? "reachable" : "unreachable")")
                if reachable && wasUnreachable && self.pendingCount > 0 {
                    logger.info("OfflineSyncManager: reconnected — triggering sync  pending=\(self.pendingCount)")
                    // Give the network stack ~2s to fully establish before hitting remote endpoints.
                    try? await Task.sleep(for: .seconds(2))
                    await self.performSync()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func performSync() async {
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        let ctx = stack.newBackgroundContext()
        var pendingItems: [QuizAnswerEntity] = []

        do {
            pendingItems = try await ctx.perform { try ctx.fetchPendingAnswers() }
        } catch {
            logger.error("OfflineSyncManager.performSync: fetch failed — \(error.localizedDescription)")
            lastSyncError = "Failed to load pending answers."
            return
        }

        guard !pendingItems.isEmpty else {
            logger.debug("OfflineSyncManager.performSync: nothing to sync")
            return
        }

        logger.info("OfflineSyncManager.performSync: start  count=\(pendingItems.count)")

        // Chunk into batches to avoid oversized request bodies
        let batches = stride(from: 0, to: pendingItems.count, by: maxBatchSize).map {
            Array(pendingItems[$0 ..< min($0 + maxBatchSize, pendingItems.count)])
        }

        var totalSynced = 0
        for batch in batches {
            let payloads = batch.map { $0.toSyncPayload() }
            do {
                let response: SyncResponse = try await apiClient.request(.syncAnswers(payloads))
                logger.info("OfflineSyncManager.performSync: batch ok  synced=\(response.synced)  skipped=\(response.skipped)")

                // Mark rows as synced on background context
                await ctx.perform {
                    batch.forEach { $0.synced = true }
                    self.stack.save(ctx)
                }
                totalSynced += batch.count
            } catch {
                logger.error("OfflineSyncManager.performSync: batch failed — \(error.localizedDescription)")
                lastSyncError = (error as? APIError)?.userMessage ?? error.localizedDescription
                // Stop on first batch failure — retry on next reconnect
                break
            }
        }

        logger.info("OfflineSyncManager.performSync: complete  synced=\(totalSynced)/\(pendingItems.count)")
        refreshPendingCount()
    }

    private func refreshPendingCount() {
        let ctx = stack.viewContext
        let request: NSFetchRequest<QuizAnswerEntity> = QuizAnswerEntity.fetchRequest()
        request.predicate = NSPredicate(format: "synced == NO")
        let count = (try? ctx.count(for: request)) ?? 0
        if pendingCount != count {
            pendingCount = count
            logger.debug("OfflineSyncManager: pendingCount=\(count)")
        }
    }
}
