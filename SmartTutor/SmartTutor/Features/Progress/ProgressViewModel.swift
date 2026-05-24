//
//  ProgressViewModel.swift
//  SmartTutor
//
//  Sprint 6 — Loads weekly progress from GET /progress/:studentId.
//  Sprint 9 — Offline cache + auto-refresh on reconnect.
//

import Foundation
import Observation
import os.log

private let logger = AppLogger.progress

@Observable @MainActor
final class ProgressViewModel {

    private(set) var progressData: ProgressResponse? = nil
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String? = nil
    private(set) var isShowingCachedData: Bool = false

    private let apiClient: APIClient
    private let syncManager: OfflineSyncManager
    private var currentStudentId: String = ""

    init(apiClient: APIClient = .shared, syncManager: OfflineSyncManager = .shared) {
        self.apiClient   = apiClient
        self.syncManager = syncManager
        observeReachability()
    }

    // MARK: - Load

    func load(studentId: String) async {
        guard !isLoading else { return }
        currentStudentId = studentId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data: ProgressResponse = try await apiClient.request(.progress(studentId: studentId))
            progressData = data
            isShowingCachedData = false
            cacheProgress(data, for: studentId)
            logger.info("ProgressViewModel.load: ok  topics=\(data.topics.count)  weak=\(data.weakTopics.count)")
        } catch {
            // Fall back to cache; surface an error only if cache is also empty.
            if loadCachedProgress(for: studentId) {
                logger.info("ProgressViewModel.load: offline — showing cached progress")
            } else {
                errorMessage = (error as? APIError)?.userMessage ?? "Failed to load progress."
                logger.error("ProgressViewModel.load: failed  \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reconnect auto-refresh

    private func observeReachability() {
        Task { [weak self] in
            guard let self else { return }
            var previous = syncManager.isNetworkReachable
            while !Task.isCancelled {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.syncManager.isNetworkReachable
                    } onChange: {
                        cont.resume()
                    }
                }
                let current = syncManager.isNetworkReachable
                if current && !previous && !currentStudentId.isEmpty {
                    logger.info("ProgressViewModel: network restored — refreshing progress")
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        guard let self else { return }
                        await self.load(studentId: self.currentStudentId)
                    }
                }
                previous = current
            }
        }
    }

    // MARK: - UserDefaults cache

    private func cacheKey(for studentId: String) -> String { "cached_progress_\(studentId)" }

    private func cacheProgress(_ data: ProgressResponse, for studentId: String) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: cacheKey(for: studentId))
    }

    /// Returns true if cached data was loaded successfully.
    @discardableResult
    private func loadCachedProgress(for studentId: String) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: studentId)),
              let cached = try? JSONDecoder().decode(ProgressResponse.self, from: data) else {
            return false
        }
        progressData = cached
        isShowingCachedData = true
        return true
    }
}
