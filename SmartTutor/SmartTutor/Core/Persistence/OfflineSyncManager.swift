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
import UIKit

private let logger = AppLogger.offline

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
    /// Polling task — runs every 3 s while the app is active to catch NWPathMonitor stalls (common in simulator).
    /// Stored as nonisolated so it can be cancelled safely from deinit.
    nonisolated(unsafe) private var pollingTask: Task<Void, Never>?

    // MARK: Init

    init(stack: CoreDataStack = .shared, apiClient: APIClient = .shared) {
        self.stack     = stack
        self.apiClient = apiClient
        refreshPendingCount()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
        pollingTask?.cancel()
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
        // Any successful HTTP response is ground truth that the network is up.
        // Wire this before NWPathMonitor so the callback is set before any requests fire.
        apiClient.onNetworkSuccess = { [weak self] in
            guard let self else { return }
            logger.debug("OfflineSyncManager: onNetworkSuccess fired — marking reachable")
            self.markReachable()
        }

        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyReachability(reachable)
            }
        }
        monitor.start(queue: monitorQueue)

        // NWPathMonitor can stall in the simulator and miss reconnect events.
        // Poll monitor.currentPath every 3 s while the app is active as a fallback.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.startPolling() } }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.stopPolling() } }

        // Start immediately (init happens while app is active).
        startPolling()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                // Only probe when we think we're offline — avoids noise when already online.
                // We do NOT re-read monitor.currentPath.status here: NWPathMonitor can stall
                // and its currentPath stays unsatisfied even when URLSession traffic flows.
                // Instead, fire a real HEAD /health to confirm actual reachability.
                guard !self.isNetworkReachable else { continue }
                logger.info("OfflineSyncManager: polling probe — isNetworkReachable=false, probing /health")
                let reachable = await self.probeConnectivity()
                if reachable {
                    logger.info("OfflineSyncManager: probe=reachable — applying")
                    self.applyReachability(true)
                } else {
                    logger.debug("OfflineSyncManager: probe=unreachable")
                }
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Lightweight connectivity probe: sends HEAD to /health (no auth required).
    /// Returns true if we get any HTTP response — even a non-200 proves DNS + TCP work.
    private func probeConnectivity() async -> Bool {
        let url = AppConfig.prodURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }

    /// Force reachability to false immediately — called by StudyViewModel when a /ask
    /// request fails with .noNetwork so the flag is corrected without waiting for the
    /// next 3-second polling cycle. This guarantees the false→true transition that
    /// `observeReachability` needs to trigger an offline-queue replay.
    func markUnreachable() {
        logger.warning("OfflineSyncManager: markUnreachable() called — forcing isNetworkReachable=false")
        applyReachability(false)
    }

    /// Force reachability to true immediately — called by StudyViewModel when a /ask
    /// request succeeds. NWPathMonitor can stall and never report reconnection even
    /// while URLSession traffic flows; a successful HTTP response is ground truth that
    /// the network is up, so we drive the flag here rather than waiting for the poll.
    func markReachable() {
        // applyReachability's guard makes this a free no-op when already reachable
        if !isNetworkReachable {
            logger.info("OfflineSyncManager: markReachable() called — forcing isNetworkReachable=true")
        }
        applyReachability(true)
    }

    /// Central place to update reachability state and trigger reconnect side-effects.
    private func applyReachability(_ reachable: Bool) {
        guard reachable != isNetworkReachable else { return }   // no-op if unchanged
        let wasUnreachable = !isNetworkReachable
        isNetworkReachable = reachable
        logger.info("OfflineSyncManager: network=\(reachable ? "reachable" : "unreachable")")
        if reachable && wasUnreachable && pendingCount > 0 {
            logger.info("OfflineSyncManager: reconnected — triggering sync  pending=\(self.pendingCount)")
            Task {
                // Give the network stack ~2 s to fully establish before hitting remote endpoints.
                try? await Task.sleep(for: .seconds(2))
                await performSync()
            }
        }
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
